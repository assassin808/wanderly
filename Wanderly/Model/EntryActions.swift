import Foundation
import SwiftData
import WanderlyCore

/// 所有会影响提醒的修改都走这里：保存后重排通知。
enum EntryActions {
    static func capture(_ text: String, due: Date, hasTime: Bool, in context: ModelContext) {
        let trimmed = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !trimmed.isEmpty else { return }
        context.insert(Entry(text: trimmed, due: due, hasTime: hasTime))
        save(context)
    }

    static func set(_ entry: Entry, to state: EntryState, in context: ModelContext) {
        entry.state = state
        save(context)
    }

    static func snooze(_ entry: Entry, in context: ModelContext) {
        entry.snooze()
        save(context)
    }

    static func delete(_ entry: Entry, in context: ModelContext) {
        context.delete(entry)
        save(context)
    }

    /// 把分享扩展放进 App Group 收件箱的速记导入数据库。
    @discardableResult
    static func importInbox(into context: ModelContext) -> Int {
        guard let directory = SharedContainer.defaultURL else { return 0 }
        let items = SharedContainer.takeInbox(in: directory)
        for item in items {
            let entry = Entry(text: item.text, due: item.due, hasTime: item.hasTime)
            entry.createdAt = item.createdAt
            context.insert(entry)
        }
        if !items.isEmpty {
            try? context.save()
        }
        return items.count
    }

    static func save(_ context: ModelContext) {
        try? context.save()
        Reminders.shared.scheduleSoon()
    }
}
