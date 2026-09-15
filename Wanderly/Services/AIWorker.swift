import Foundation
import Observation
import os
import SwiftData
import WanderlyCore
#if os(iOS)
import UIKit
#endif

/// 在后台调用 AI：整理新记录、回复对话、Beta 浇水和漫游。
/// 进度和结果都存在记录里，所以离开页面、切到后台，甚至 App 被关掉，下次都能接着处理。
///
/// AI 请求要等几秒到几十秒，期间用户可能把记录删掉了。删掉并保存后再读旧对象的属性可能崩溃，
/// 所以请求前只记下 id，请求回来后用 `liveEntry(_:)` 重新取。
@Observable
final class AIWorker {
    static let shared = AIWorker()

    /// 正在等 AI 回复的记录，对话里用来显示「正在想」。
    private(set) var replying: Set<UUID> = []
    private(set) var wandering = false
    @ObservationIgnored private var organizing = false
    @ObservationIgnored private var needsAnotherPass = false
    @ObservationIgnored private let log = Logger(subsystem: "io.github.assassin808.wanderly", category: "ai")

    /// 这台设备的标识，避免 iPhone 和 Mac 同时处理同一条。
    static let deviceID: String = {
        let key = "aiDeviceID"
        if let id = UserDefaults.standard.string(forKey: key) { return id }
        let id = UUID().uuidString
        UserDefaults.standard.set(id, forKey: key)
        return id
    }()

    /// 示例数据默认不调用 AI，需要时用 `-demoAI` 启动。
    var isEnabled: Bool {
        !Persistence.isDemo || ProcessInfo.processInfo.arguments.contains("-demoAI")
    }

    private var context: ModelContext { Persistence.container.mainContext }

    private struct Credentials {
        let provider: AIProvider
        let key: String
    }

    private func credentials() -> Credentials? {
        let provider = Preferences.aiProvider
        guard let key = APIKeyStore.effectiveKey(for: provider) else { return nil }
        return Credentials(provider: provider, key: key)
    }

    /// 重新取一次记录；已经被删掉就返回 nil。
    private func liveEntry(_ id: UUID) -> Entry? {
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        guard let entry = try? context.fetch(descriptor).first, !entry.isDeleted else { return nil }
        return entry
    }

    func kick() {
        Task { await processPending() }
    }

    // MARK: 整理

    func processPending() async {
        guard isEnabled else { return }
        // 正在处理时来的新请求不能丢（比如刚打开 App 就记了一条，或者连着记两条）：等这一轮结束再跑一轮。
        guard !organizing else {
            needsAnotherPass = true
            return
        }
        organizing = true
        defer { organizing = false }
        repeat {
            needsAnotherPass = false
            await runPass()
        } while needsAnotherPass
    }

    private func runPass() async {
        let now = Date.now
        let entries = (try? context.fetch(FetchDescriptor<Entry>())) ?? []
        // 已经完成或放弃的不再花 AI 额度，比如升级前留下的旧记录。
        let toOrganize = entries.filter { entry in
            guard entry.state.isActive else { return false }
            return switch entry.aiStatus {
            case .pending: true
            // 另一台设备认领后几分钟没结果，或者上次失败过了一段时间，就再试一次。
            case .processing: (entry.aiClaimedAt ?? .distantPast) < now.addingTimeInterval(-180)
            case .failed: (entry.aiClaimedAt ?? .distantPast) < now.addingTimeInterval(-1800)
            case .done: false
            }
        }.map(\.id)
        // 欠着的回复：这台设备上发出去的（比如等回复时 App 被关掉了），或者上次失败过了一段时间。
        let owedReplies = entries.filter { entry in
            entry.awaitingReply
                && (entry.replyError.isEmpty || entry.updatedAt < now.addingTimeInterval(-600))
                && (entry.aiDevice == Self.deviceID || entry.updatedAt < now.addingTimeInterval(-300))
        }.map(\.id)

        for id in toOrganize {
            if let entry = liveEntry(id) { await organize(entry) }
        }
        for id in owedReplies {
            if let entry = liveEntry(id) { await sendReply(entry) }
        }
    }

    func retryOrganize(_ entry: Entry) {
        entry.aiStatus = .pending
        entry.aiError = ""
        try? context.save()
        kick()
    }

    private func organize(_ entry: Entry) async {
        guard let credentials = credentials() else {
            log.error("organize skipped: no API key")
            entry.aiError = AIError.missingKey.localizedDescription
            try? context.save()
            return
        }
        let id = entry.id
        entry.aiStatus = .processing
        entry.aiClaimedAt = .now
        entry.aiDevice = Self.deviceID
        entry.aiError = ""
        try? context.save()
        log.notice("organize start with \(credentials.provider.rawValue, privacy: .public)")

        let input = Organizer.Input(
            text: entry.fullText, urgency: entry.urgency, knownDue: entry.dueLabel,
            today: Date.now.formatted(date: .complete, time: .omitted))
        do {
            let result = try await withBackgroundTime {
                try await withRetries {
                    try await Organizer.run(input, provider: credentials.provider, apiKey: credentials.key)
                }
            }
            guard let entry = liveEntry(id) else { return }
            log.notice("organize done: \(result.category.rawValue, privacy: .public), \(result.questions.count) questions")
            // 用户在等待期间自己改过的标题和类别不覆盖。
            if entry.aiTitle.trimmed.isEmpty { entry.aiTitle = result.title }
            if entry.category == nil { entry.category = result.category }
            entry.aiSummary = result.summary
            if !entry.hasDue, let due = result.due, due.isUpcoming(now: .now) {
                entry.due = due.date
                entry.hasTime = due.hasTime
                entry.hasDue = true
            }
            if result.questions.isEmpty {
                // 没什么要补充的，就不用再提醒完善。
                if entry.state == .rough { entry.state = .open }
            } else {
                let text = result.questions.count == 1
                    ? result.questions[0]
                    : result.questions.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
                EntryActions.addMessage(to: entry, role: .assistant, kind: .question, text: text, in: context)
            }
            entry.aiStatus = .done
        } catch {
            log.error("organize failed: \(error.localizedDescription, privacy: .public)")
            guard let entry = liveEntry(id) else { return }
            entry.aiStatus = .failed
            entry.aiError = error.localizedDescription
        }
        EntryActions.save(context)
    }

    // MARK: 对话

    /// 用户发一条消息：先存下来，再在后台等 AI 回复。
    func send(_ text: String, to entry: Entry) {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return }
        EntryActions.addMessage(to: entry, role: .user, kind: .chat, text: trimmed, in: context)
        entry.touch()
        entry.replyError = ""
        entry.aiDevice = Self.deviceID
        if entry.state == .rough { entry.state = .open }
        EntryActions.save(context)
        Task { await sendReply(entry) }
    }

    func retryReply(_ entry: Entry) {
        Task { await sendReply(entry) }
    }

    private func sendReply(_ entry: Entry) async {
        let id = entry.id
        guard isEnabled, liveEntry(id) != nil, entry.awaitingReply, !replying.contains(id) else { return }
        guard let credentials = credentials() else {
            log.error("reply skipped: no API key")
            entry.replyError = AIError.missingKey.localizedDescription
            try? context.save()
            return
        }
        replying.insert(id)
        defer { replying.remove(id) }
        entry.replyError = ""

        let conversation = Conversation.Context(title: entry.title, category: entry.category ?? .other, text: entry.fullText, summary: entry.aiSummary)
        let history = entry.sortedMessages.map { ChatTurn($0.role, $0.text) }
        do {
            let reply = try await withBackgroundTime {
                try await withRetries {
                    try await Conversation.reply(context: conversation, history: history, provider: credentials.provider, apiKey: credentials.key)
                }
            }
            guard let entry = liveEntry(id) else { return }
            log.notice("reply done: \(reply.count) characters")
            EntryActions.addMessage(to: entry, role: .assistant, kind: .chat, text: reply, in: context)
        } catch {
            log.error("reply failed: \(error.localizedDescription, privacy: .public)")
            guard let entry = liveEntry(id) else { return }
            entry.replyError = error.localizedDescription
        }
        EntryActions.save(context)
    }

    // MARK: Beta

    /// 想法放了一段时间没动、也没有待回答的问题时，AI 抛一个新问题。每次最多两条，避免一下子用掉太多额度。
    func waterIdeas() async {
        guard isEnabled, Preferences.betaIdeas, let credentials = credentials() else { return }
        let now = Date.now
        let cutoff = now.addingTimeInterval(-TimeInterval(Preferences.waterIntervalDays * 24 * 3600))
        let ideas = ((try? context.fetch(FetchDescriptor<Entry>())) ?? []).filter { entry in
            entry.category == .idea && entry.state.isActive && entry.urgency != .archive && entry.aiStatus == .done
                && entry.pendingQuestion == nil && !entry.awaitingReply
                && max(entry.lastActivityAt ?? entry.createdAt, entry.wateredAt ?? .distantPast) < cutoff
        }
        for idea in ideas.prefix(2) {
            let id = idea.id
            idea.wateredAt = now
            let conversation = Conversation.Context(title: idea.title, category: .idea, text: idea.fullText, summary: idea.aiSummary)
            let history = idea.sortedMessages.map { ChatTurn($0.role, $0.text) }
            do {
                let question = try await withBackgroundTime {
                    try await Watering.question(context: conversation, history: history, provider: credentials.provider, apiKey: credentials.key)
                }
                if let entry = liveEntry(id) {
                    EntryActions.addMessage(to: entry, role: .assistant, kind: .water, text: question, in: context)
                }
            } catch {
                log.error("water failed: \(error.localizedDescription, privacy: .public)")
            }
            EntryActions.save(context)
        }
    }

    /// 漫游：至少 3 个想法才有意义。自动每周最多一次，也可以在设置里手动触发。返回失败原因。
    @discardableResult
    func wander(force: Bool = false) async -> String? {
        guard isEnabled, Preferences.betaIdeas else { return nil }
        if !force, let last = Preferences.lastWanderAt, last > .now.addingTimeInterval(-7 * 24 * 3600) { return nil }
        guard let credentials = credentials() else { return AIError.missingKey.localizedDescription }
        // 请求前把需要的内容取出来，等待期间想法被删掉也不会读到失效的对象。
        let ideas = ((try? context.fetch(FetchDescriptor<Entry>())) ?? [])
            .filter { $0.category == .idea && $0.state != .dropped }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(12)
            .map { Wanderer.Idea(id: $0.id, title: $0.title, summary: $0.aiSummary) }
        guard ideas.count >= 3 else { return force ? "至少要有 3 个想法才能漫游。" : nil }

        wandering = true
        defer { wandering = false }
        Preferences.lastWanderAt = .now
        do {
            let link = try await withBackgroundTime {
                try await withRetries {
                    try await Wanderer.wander(ideas: Array(ideas), provider: credentials.provider, apiKey: credentials.key)
                }
            }
            let titles = link.sourceIDs.compactMap { id in ideas.first { $0.id == id }?.title }
            context.insert(WanderLink(title: link.title, insight: link.insight, question: link.question, sourceIDs: link.sourceIDs, sourceTitles: titles))
            try? context.save()
            return nil
        } catch {
            log.error("wander failed: \(error.localizedDescription, privacy: .public)")
            return error.localizedDescription
        }
    }

    // MARK: -

    /// 免费额度经常碰到繁忙或限流：隔几秒再试两次，还不行才把错误交给界面。
    private func withRetries<T>(_ work: () async throws -> T) async throws -> T {
        var delays: [Duration] = [.seconds(4), .seconds(12)]
        while true {
            do {
                return try await work()
            } catch let error as AIError where error.isTransient && !delays.isEmpty {
                log.notice("AI busy, retrying: \(error.localizedDescription, privacy: .public)")
                try await Task.sleep(for: delays.removeFirst())
            }
        }
    }

    /// 切到后台时请系统多给一点时间，让正在进行的请求跑完。
    private func withBackgroundTime<T>(_ work: () async throws -> T) async throws -> T {
        #if os(iOS)
        var task = UIBackgroundTaskIdentifier.invalid
        task = UIApplication.shared.beginBackgroundTask(withName: "Wanderly AI") {
            UIApplication.shared.endBackgroundTask(task)
            task = .invalid
        }
        defer {
            if task != .invalid { UIApplication.shared.endBackgroundTask(task) }
        }
        #endif
        return try await work()
    }
}
