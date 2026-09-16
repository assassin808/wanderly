import SwiftUI
import SwiftData
import WanderlyCore

struct RootView: View {
    @Environment(AppRouter.self) private var router
    @Environment(\.scenePhase) private var scenePhase
    @Query(sort: \Entry.due) private var entries: [Entry]
    @State private var editing: Entry?
    @State private var showSettings = false

    /// 只记录的不催，不算进待完善。
    private var roughCount: Int { entries.filter { $0.state == .rough && $0.urgency != .archive }.count }

    var body: some View {
        @Bindable var router = router
        NavigationStack {
            EntryListView(entries: entries) { editing = $0 }
                .navigationTitle("Wanderly")
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Button {
                            router.showRefine = true
                        } label: {
                            // iOS 26 的工具栏会把 Label 压成图标，数量就看不到了，所以只用文字。
                            Text(roughCount > 0 ? "完善 \(roughCount)" : "完善")
                        }
                        .disabled(roughCount == 0)
                        .accessibilityIdentifier("refineButton")
                    }
                    #if os(iOS)
                    ToolbarItem(placement: .topBarLeading) {
                        Button {
                            showSettings = true
                        } label: {
                            Label("设置", systemImage: "gearshape")
                        }
                        .accessibilityIdentifier("settingsButton")
                    }
                    #endif
                }
        }
        .sheet(item: $editing) { entry in
            EntryDetailView(entry: entry)
        }
        .sheet(isPresented: $router.showRefine) {
            RefineFlowView()
        }
        #if os(iOS)
        .sheet(isPresented: $showSettings) {
            NavigationStack {
                SettingsView()
                    .navigationTitle("设置")
                    .navigationBarTitleDisplayMode(.inline)
                    .toolbar {
                        ToolbarItem(placement: .confirmationAction) {
                            Button("完成") { showSettings = false }
                        }
                    }
            }
        }
        #endif
        .onOpenURL { url in
            router.handle(url)
        }
        .onChange(of: router.openEntryID) { _, id in
            guard let id else { return }
            editing = entries.first { $0.id == id }
            router.openEntryID = nil
        }
        .onChange(of: router.captureRequest) {
            editing = nil
            showSettings = false
        }
        .onChange(of: scenePhase) { _, phase in
            switch phase {
            case .active:
                Task { await AppRefresh.run() }
            case .background:
                #if os(iOS)
                AppRefresh.scheduleBackgroundRefresh()
                #endif
                Reminders.shared.scheduleSoon()
            default:
                break
            }
        }
        .task {
            if !ProcessInfo.processInfo.arguments.contains("-skipNotificationPrompt") {
                await Reminders.shared.requestAuthorizationIfNeeded()
            }
            #if DEBUG && os(iOS)
            WidgetPreviewRenderer.runIfRequested()
            #endif
            #if DEBUG
            // 调试用：Mac 上没法用脚本点开一条记录，用这个参数直接打开第一条。
            if ProcessInfo.processInfo.arguments.contains("-openEntry") {
                editing = entries.first { $0.state.isActive }
            }
            #endif
            await AppRefresh.run()
        }
    }
}
