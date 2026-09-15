import Foundation
import SwiftData
import WanderlyCore

/// 会影响提醒或 AI 的修改都走这里：保存后重排通知，需要时让 AI 在后台处理。
enum EntryActions {
    @discardableResult
    static func capture(_ text: String, urgency: Urgency, due: DetectedDue?, in context: ModelContext) -> Entry? {
        let trimmed = text.trimmed
        guard !trimmed.isEmpty else { return nil }
        let entry = Entry(text: trimmed, urgency: urgency, due: due?.date, hasTime: due?.hasTime ?? false)
        context.insert(entry)
        save(context)
        AIWorker.shared.kick()
        return entry
    }

    /// 先插入再建立关系，SwiftData 不允许给还没插入的对象设置关系。
    static func addMessage(to entry: Entry, role: ChatTurn.Role, kind: ChatMessage.Kind, text: String, in context: ModelContext) {
        let message = ChatMessage(role: role, kind: kind, text: text)
        context.insert(message)
        message.entry = entry
        entry.updatedAt = .now
    }

    static func set(_ entry: Entry, to state: EntryState, in context: ModelContext) {
        entry.state = state
        entry.touch()
        save(context)
    }

    static func snooze(_ entry: Entry, in context: ModelContext) {
        entry.snooze()
        save(context)
    }

    /// 「稍后提醒」：几个小时后再提醒完善。
    static func remindLater(_ entry: Entry, hours: Int = 3, in context: ModelContext) {
        entry.snoozedUntil = Calendar.current.date(byAdding: .hour, value: hours, to: .now)
        save(context)
    }

    static func delete(_ entry: Entry, in context: ModelContext) {
        context.delete(entry)
        save(context)
    }

    /// 把分享扩展放进 App Group 收件箱的记录导入数据库，交给 AI 整理。
    @discardableResult
    static func importInbox(into context: ModelContext) -> Int {
        guard let directory = SharedContainer.defaultURL else { return 0 }
        let items = SharedContainer.takeInbox(in: directory)
        for item in items {
            let entry = Entry(text: item.text, urgency: item.urgency, due: item.hasDue ? item.due : nil, hasTime: item.hasTime)
            entry.createdAt = item.createdAt
            context.insert(entry)
        }
        if !items.isEmpty {
            save(context)
            AIWorker.shared.kick()
        }
        return items.count
    }

    /// 采纳漫游结果：变成一条新的想法记录，AI 的问题放进对话。
    static func accept(_ link: WanderLink, in context: ModelContext) {
        let entry = Entry(text: "\(link.title)\n\n\(link.insight)\n\n来自：\(link.sourceTitles)", urgency: .later)
        entry.aiTitle = link.title
        entry.category = .idea
        entry.aiSummary = link.insight
        entry.aiStatus = .done
        context.insert(entry)
        if !link.question.isEmpty {
            addMessage(to: entry, role: .assistant, kind: .question, text: link.question, in: context)
        }
        context.delete(link)
        save(context)
    }

    static func save(_ context: ModelContext) {
        try? context.save()
        Reminders.shared.scheduleSoon()
    }
}

extension Entry {
    var markdown: String {
        MarkdownExport.entry(
            title: title, category: category, urgency: urgency, due: dueLabel,
            text: text, summary: aiSummary,
            messages: sortedMessages.map { MarkdownExport.Message(role: $0.role, text: $0.text) })
    }
}
