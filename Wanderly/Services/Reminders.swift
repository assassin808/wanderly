import CoreData
import Foundation
import SwiftData
import UserNotifications
import WanderlyCore

/// 把 ReminderPlanner 算出的计划变成本地通知，并处理通知上的操作。
final class Reminders: NSObject, UNUserNotificationCenterDelegate {
    static let shared = Reminders()

    private enum Category {
        static let entry = "ENTRY"
        static let evening = "EVENING"
    }

    private enum Action {
        static let done = "DONE"
        static let snooze = "SNOOZE"
        static let refine = "REFINE"
    }

    private let center = UNUserNotificationCenter.current()
    private var pending: Task<Void, Never>?

    func start() {
        Preferences.registerDefaults()
        center.delegate = self
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Category.entry, actions: [
                UNNotificationAction(identifier: Action.done, title: "完成", options: []),
                UNNotificationAction(identifier: Action.snooze, title: "推迟到明天", options: []),
            ], intentIdentifiers: []),
            UNNotificationCategory(identifier: Category.evening, actions: [
                UNNotificationAction(identifier: Action.refine, title: "去完善", options: [.foreground]),
            ], intentIdentifiers: []),
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

        // 只清掉自己排的提醒，不动还没弹出的测试通知。
        let planned = await center.pendingNotificationRequests().map(\.identifier).filter { !$0.hasPrefix("test-") }
        center.removePendingNotificationRequests(withIdentifiers: planned)
        let closedIDs = snapshots.filter { !$0.state.isActive }.flatMap { ["due-\($0.id.uuidString)", "check-\($0.id.uuidString)"] }
        center.removeDeliveredNotifications(withIdentifiers: closedIDs)

        let needsAttention = snapshots.filter {
            $0.state == .rough || ($0.state.isActive && DueText.isOverdue(due: $0.due, hasTime: $0.hasTime, now: now))
        }.count
        try? await center.setBadgeCount(Preferences.remindersOnThisDevice ? needsAttention : 0)

        guard Preferences.remindersOnThisDevice else { return }
        for item in ReminderPlanner.plan(entries: snapshots, settings: Preferences.reminderSettings, now: now) {
            try? await center.add(request(for: item))
        }
    }

    func sendTest() async {
        await requestAuthorizationIfNeeded()
        let content = UNMutableNotificationContent()
        content.title = "Wanderly"
        content.body = "提醒可以正常收到。"
        content.sound = .default
        let trigger = UNTimeIntervalNotificationTrigger(timeInterval: 3, repeats: false)
        try? await center.add(UNNotificationRequest(identifier: "test-\(UUID().uuidString)", content: content, trigger: trigger))
    }

    private func request(for item: PlannedNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = item.title
        content.body = item.body
        content.sound = .default
        content.threadIdentifier = item.kind.rawValue
        switch item.kind {
        case .due, .check: content.categoryIdentifier = Category.entry
        case .evening: content.categoryIdentifier = Category.evening
        case .morning: break
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
        switch action {
        case Action.done, Action.snooze:
            guard let entryID, let entry = entry(with: entryID) else { return }
            if action == Action.done {
                entry.state = .done
            } else {
                entry.snooze()
            }
            try? Persistence.container.mainContext.save()
            await reschedule()
        case Action.refine:
            AppRouter.shared.showRefine = hasRoughEntries()
        case UNNotificationDefaultActionIdentifier:
            if let entryID {
                AppRouter.shared.openEntryID = entryID
            } else if category == Category.evening {
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

    private func hasRoughEntries() -> Bool {
        let rough = EntryState.rough.rawValue
        let descriptor = FetchDescriptor<Entry>(predicate: #Predicate { $0.stateRaw == rough })
        return ((try? Persistence.container.mainContext.fetchCount(descriptor)) ?? 0) > 0
    }
}
