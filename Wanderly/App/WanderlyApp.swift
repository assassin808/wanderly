import SwiftUI
import SwiftData

@main
struct WanderlyApp: App {
    init() {
        Reminders.shared.start()
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
