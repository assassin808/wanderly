import SwiftUI
import SwiftData

@main
struct WanderlyApp: App {
    init() {
        // 要在第一次访问 Persistence.container 之前开始监听，才能收到 setup 事件。
        SyncStatus.shared.start()
        Reminders.shared.start()
        #if os(macOS)
        AppRefresh.startPeriodicRefresh()
        #endif
        if Persistence.isDemo, ProcessInfo.processInfo.arguments.contains("-refine") {
            AppRouter.shared.showRefine = true
        }
    }

    var body: some Scene {
        WindowGroup(id: "main") {
            RootView()
                .environment(AppRouter.shared)
        }
        .modelContainer(Persistence.container)
        #if os(macOS)
        .defaultSize(width: 520, height: 760)
        #else
        .backgroundTask(.appRefresh(AppRefresh.taskIdentifier)) {
            await AppRefresh.run()
            await AppRefresh.scheduleBackgroundRefresh()
        }
        #endif

        #if os(macOS)
        MenuBarExtra("Wanderly", systemImage: "square.and.pencil") {
            MenuBarCapture()
        }
        .menuBarExtraStyle(.window)
        .modelContainer(Persistence.container)

        Settings {
            SettingsView()
                .frame(minWidth: 460, minHeight: 520)
        }
        #endif
    }
}
