import CoreData
import Foundation
import SwiftData
import UserNotifications
import WanderlyCore

/// 把 ReminderPlanner 算出的计划变成本地通知，并处理通知上的操作。
final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Reminders()

    private enum Category {
        /// 做完了吗 / 还在进行吗：完成、明天再问。
        static let entry = "ENTRY"
        /// 去完善：回答、稍后提醒。
        static let refine = "REFINE"
        /// 好几条等着完善：点开进入完善流程。
        static let refineDigest = "REFINE_DIGEST"
    }

    private enum Action {
        static let done = "DONE"
        static let snooze = "SNOOZE"
        static let answer = "ANSWER"
        static let later = "LATER"
    }

    private let center = UNUserNotificationCenter.current()
    private var pending: Task<Void, Never>?

    func start() {
        Preferences.registerDefaults()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.entry, actions: [
                UNNotificationAction(identifier: Action.done, title: "完成", options: []),
                UNNotificationAction(identifier: Action.snooze, title: "明天再问", options: []),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.refine, actions: [
                UNNotificationAction(identifier: Action.answer, title: "回答", options: [.foreground]),
                UNNotificationAction(identifier: Action.later, title: "3 小时后提醒", options: []),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.refineDigest, actions: [], intentIdentifiers: []),
        ])
        // 另一台设备改了数据，iCloud 同步过来之后重排提醒。
        NotificationCenter.default.addObserver(forName: .NSPersistentStoreRemoteChange, object: nil, queue: .main) { _ in
            MainActor.assumeIsolated { Reminders.shared.scheduleSoon() }
        }
    }

    func requestAuthorizationIfNeeded() async {
        let settings = await center.notificationSettings()
        guard settings.authorizationStatus == .notDetermined else { return }
        _ = try? await center.requestAuthorization(options: [.alert, .sound, .badge])
    }

    /// 合并短时间内的多次修改。
    func scheduleSoon() {
        pending?.cancel()
        pending = Task {
            try? await Task.sleep(for: .milliseconds(800))
            guard !Task.isCancelled else { return }
            await reschedule()
        }
    }

    func reschedule() async {
        let context = Persistence.container.mainContext
        let snapshots = ((try? context.fetch(FetchDescriptor<Entry>())) ?? []).map(\.snapshot)
        let now = Date.now
        WidgetBridge.publish(snapshots)

        // 只清掉自己排的提醒，不动还没弹出的测试通知。
        let planned = await center.pendingNotificationRequests().map(\.identifier).filter { !$0.hasPrefix("test-") }
        center.removePendingNotificationRequests(withIdentifiers: planned)
        let closed = snapshots.filter { !$0.state.isActive }.map(\.id.uuidString)
        let delivered = await center.deliveredNotifications().map(\.request.identifier)
        center.removeDeliveredNotifications(withIdentifiers: delivered.filter { id in closed.contains { id.contains($0) } })

        let needsAttention = snapshots.filter { entry in
            entry.state.isActive && entry.urgency != .archive
                && (entry.state == .rough || (entry.hasDue && DueText.isOverdue(due: entry.due, hasTime: entry.hasTime, now: now)))
        }.count
        try? await center.setBadgeCount(Preferences.remindersOnThisDevice ? needsAttention : 0)

        guard Preferences.remindersOnThisDevice else { return }
        for item in ReminderPlanner.plan(entries: snapshots, settings: Preferences.reminderSettings, now: now) {
            try? await center.add(request(for: item))
        }
    }

    /// 有待办时，测试通知带上「完成 / 明天再问」按钮，作用在最早到期的那一条上。
    func sendTest() async {
        await requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = "Wanderly"
        content.body = "提醒可以正常收到。"
        content.sound = .default
        if let entry = earliestActiveEntry() {
            content.title = "测试：做完了吗？"
            content.body = "提醒可以正常收到。长按可以直接处理：\(entry.title)"
            content.categoryIdentifier = Category.entry
            content.userInfo = ["entryID": entry.id.uuidString]
        }
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 5, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger))
    }

    private func request(for item: PlannedNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        content.threadIdentifier = item.kind.rawValue
        switch item.kind {
        case .due, .check, .checkIn: content.categoryIdentifier = Category.entry
        case .refine, .water: content.categoryIdentifier = Category.refine
        case .refineDigest: content.categoryIdentifier = Category.refineDigest
        case .morning, .checkInDigest, .keepAlive: break
        }
        if let entryID = item.entryID {
            content.userInfo = ["entryID": entryID.uuidString]
        }
        let components = Calendar.current.dateComponents([.year, .month, .day, .hour, .minute, .second], from: item.fireDate)
        let trigger = UNCalendarNotificationTrigger(dateMatching: components, repeats: false)
        return UNNotificationRequest(identifier: item.id, content: content, trigger: trigger)
    }

    /// 已经排好、还没发出的提醒，按时间排序。
    func upcoming(limit: Int = 6) async -> [UpcomingReminder] {
        let requests = await center.pendingNotificationRequests()
        let items = requests.compactMap { request -> UpcomingReminder? in
            guard let trigger = request.trigger as? UNCalendarNotificationTrigger,
                  let date = trigger.nextTriggerDate() else { return nil }
            return UpcomingReminder(id: request.identifier, title: request.content.title, body: request.content.body, date: date)
        }
        return Array(items.sorted { $0.date < $1.date }.prefix(limit))
    }

    // MARK: UNUserNotificationCenterDelegate

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .list, .sound]
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter, didReceive response: UNNotificationResponse) async {
        let action = response.actionIdentifier
        let content = response.notification.request.content
        let entryID = (content.userInfo["entryID"] as? String).flatMap(UUID.init(uuidString:))
        let category = content.categoryIdentifier
        await handle(action: action, category: category, entryID: entryID)
    }

    private func handle(action: String, category: String, entryID: UUID?) async {
        let context = Persistence.container.mainContext
        switch action {
        case Action.done, Action.snooze, Action.later:
            guard let entryID, let entry = entry(with: entryID) else { return }
            switch action {
            case Action.done:
                entry.state = .done
                entry.touch()
            case Action.snooze:
                entry.snooze()
            default:
                entry.snoozedUntil = Calendar.current.date(byAdding: .hour, value: 3, to: .now)
            }
            try? context.save()
            await reschedule()
        case Action.answer, UNNotificationDefaultActionIdentifier:
            if let entryID {
                AppRouter.shared.openEntryID = entryID
            } else if category == Category.refineDigest {
                AppRouter.shared.showRefine = hasRoughEntries()
            }
        default:
            break
        }
    }

    private func entry(with id: UUID) -> Entry? {
        var descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.id == id })
        descriptor.fetchLimit = 1
        return try? Persistence.container.mainContext.fetch(descriptor).first
    }

    private func earliestActiveEntry() -> Entry? {
        let rough = EntryState.rough.rawValue
        let open = EntryState.open.rawValue
        var descriptor = FetchDescriptor<Entry>(
            predicate: #Predicate { $0.stateRaw == rough || $0.stateRaw == open },
            sortBy: [SortDescriptor(\.due)])
        descriptor.fetchLimit = 1
        return try? Persistence.container.mainContext.fetch(descriptor).first
    }

    private func hasRoughEntries() -> Bool {
        let rough = EntryState.rough.rawValue
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.stateRaw == rough })
        return ((try? Persistence.container.mainContext.fetchCount(descriptor)) ?? 0) > 0
    }
}
