import Foundation
import SwiftData
import WanderlyCore

/// AI 整理一条记录的进度。
enum AIStatus: String {
    case pending
    case processing
    case done
    case failed
}

/// 唯一的记录类型。CloudKit 同步要求所有属性有默认值或可选，关系也必须可选。
@Model
final class Entry {
    var id: UUID = UUID()
    /// 记下的原文，可以是一整段话。
    var text: String = ""
    var details: String = ""
    var nextStep: String = ""
    var due: Date = Date()
    var hasTime: Bool = false
    /// 有没有截止日期。早期版本的记录都有。
    var hasDue: Bool = true
    var urgencyRaw: String = Urgency.soon.rawValue
    var stateRaw: String = EntryState.rough.rawValue
    var createdAt: Date = Date()
    var updatedAt: Date = Date()
    var refinedAt: Date?
    var closedAt: Date?
    var snoozeCount: Int = 0
    /// 用户最近一次处理这条记录的时间，提醒从这里重新计时。
    var lastActivityAt: Date?
    var snoozedUntil: Date?

    var categoryRaw: String = ""
    var aiTitle: String = ""
    var aiSummary: String = ""
    var aiStatusRaw: String = AIStatus.pending.rawValue
    var aiError: String = ""
    var aiClaimedAt: Date?
    /// 最近发起 AI 请求的设备，避免 iPhone 和 Mac 同时处理同一条。
    var aiDevice: String = ""
    var replyError: String = ""
    var wateredAt: Date?

    @Relationship(deleteRule: .cascade, inverse: \ChatMessage.entry)
    var messages: [ChatMessage]? = []

    init(text: String, urgency: Urgency = .soon, due: Date? = nil, hasTime: Bool = false, state: EntryState = .rough) {
        self.text = text
        self.urgencyRaw = urgency.rawValue
        self.hasDue = due != nil
        self.due = due ?? Date()
        self.hasTime = hasTime
        self.stateRaw = state.rawValue
    }

    var state: EntryState {
        get { EntryState(rawValue: stateRaw) ?? .rough }
        set {
            stateRaw = newValue.rawValue
            updatedAt = .now
            switch newValue {
            case .rough:
                closedAt = nil
            case .open:
                refinedAt = refinedAt ?? .now
                closedAt = nil
            case .done, .dropped:
                closedAt = .now
            }
        }
    }

    var urgency: Urgency {
        get { Urgency(rawValue: urgencyRaw) ?? .soon }
        set { urgencyRaw = newValue.rawValue }
    }

    var category: EntryCategory? {
        get { EntryCategory(rawValue: categoryRaw) }
        set { categoryRaw = newValue?.rawValue ?? "" }
    }

    var aiStatus: AIStatus {
        get { AIStatus(rawValue: aiStatusRaw) ?? .pending }
        set { aiStatusRaw = newValue.rawValue }
    }

    /// 原文第一行。
    var firstLine: String {
        let line = text.split(whereSeparator: \.isNewline).first.map(String.init) ?? ""
        let trimmed = line.trimmed
        return trimmed.isEmpty ? "（空白）" : trimmed
    }

    /// AI 起的标题优先，否则用原文第一行。
    var title: String {
        aiTitle.trimmed.isEmpty ? firstLine : aiTitle.trimmed
    }

    var sortedMessages: [ChatMessage] {
        (messages ?? []).sorted { $0.createdAt < $1.createdAt }
    }

    /// 最后一条是用户说的，说明还欠一条 AI 回复。
    var awaitingReply: Bool {
        sortedMessages.last?.role == .user
    }

    /// 还没回答的 AI 追问或浇水问题：末尾连续几条 AI 消息里最早的一条问题。普通的 AI 回复不算。
    var pendingQuestion: ChatMessage? {
        let list = sortedMessages
        guard list.last?.role == .assistant else { return nil }
        return list.reversed().prefix { $0.role == .assistant }.last { $0.kind != .chat }
    }

    /// 给 AI 看的完整内容：原文，加上旧版本留下的细节和下一步。
    var fullText: String {
        var parts = [text]
        if !details.trimmed.isEmpty { parts.append("细节：\(details.trimmed)") }
        if !nextStep.trimmed.isEmpty { parts.append("下一步：\(nextStep.trimmed)") }
        return parts.joined(separator: "\n\n")
    }

    var dueLabel: String? {
        hasDue ? DueText.describe(due: due, hasTime: hasTime, now: .now) : nil
    }

    var snapshot: EntrySnapshot {
        let question = pendingQuestion
        return EntrySnapshot(
            id: id, title: title, due: due, hasTime: hasTime, state: state, urgency: urgency, hasDue: hasDue,
            createdAt: createdAt, lastActivityAt: lastActivityAt, refinedAt: refinedAt, snoozedUntil: snoozedUntil,
            prompt: question.map { ChatMessage.firstQuestion(in: $0.text) },
            promptAt: question?.kind == .water ? question?.createdAt : nil)
    }

    /// 用户动过这条记录：提醒从现在重新计时。
    func touch() {
        lastActivityAt = .now
        updatedAt = .now
    }

    /// 有截止日期的推迟截止日期；没有的明天再提醒。
    func snooze(days: Int = 1) {
        if hasDue {
            due = DueMath.snoozed(due: due, hasTime: hasTime, days: days, now: .now)
        } else {
            snoozedUntil = Calendar.current.date(byAdding: .day, value: days, to: .now)
        }
        snoozeCount += 1
        updatedAt = .now
    }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
