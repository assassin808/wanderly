import AppIntents

/// 控制中心、锁屏控件和操作按钮用：打开 App 并聚焦速记输入框。App 和小组件扩展共用这个文件。
struct OpenCaptureIntent: AppIntent {
    static let title: LocalizedStringResource = "打开速记"
    static let description = IntentDescription("打开 Wanderly，直接开始记一件事。")
    static let openAppWhenRun = true

    @MainActor
    func perform() async throws -> some IntentResult {
        #if !WIDGET_EXTENSION
        AppRouter.shared.requestCapture()
        #endif
        return .result()
    }
}
