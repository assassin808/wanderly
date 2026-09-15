import Foundation
#if os(iOS)
import BackgroundTasks
#endif

/// 导入分享收件箱、重排提醒、让 AI 处理积压的事。App 回到前台、iOS 后台刷新、Mac 定时任务都会调用。
enum AppRefresh {
    static let taskIdentifier = "io.github.assassin808.wanderly.refresh"

    static func run() async {
        if !Persistence.isDemo {
            EntryActions.importInbox(into: Persistence.container.mainContext)
        }
        await Reminders.shared.reschedule()
        await AIWorker.shared.processPending()
        await AIWorker.shared.waterIdeas()
        await AIWorker.shared.wander()
    }

    #if os(iOS)
    /// 请系统每天凌晨四点左右唤醒一次，这样不打开 App 时提醒也能继续往后排。
    static func scheduleBackgroundRefresh() {
        let calendar = Calendar.current
        let tomorrow = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: .now))!
        let request = BGAppRefreshTaskRequest(identifier: taskIdentifier)
        request.earliestBeginDate = calendar.date(bySettingHour: 4, minute: 0, second: 0, of: tomorrow)
        try? BGTaskScheduler.shared.submit(request)
    }
    #endif

    #if os(macOS)
    private static var scheduler: NSBackgroundActivityScheduler?

    /// Mac 上 App 常驻菜单栏，每隔几小时处理一次。
    static func startPeriodicRefresh() {
        let activity = NSBackgroundActivityScheduler(identifier: taskIdentifier)
        activity.repeats = true
        activity.interval = 3 * 60 * 60
        activity.schedule { completion in
            Task { @MainActor in
                await AppRefresh.run()
                completion(.finished)
            }
        }
        scheduler = activity
    }
    #endif
}
