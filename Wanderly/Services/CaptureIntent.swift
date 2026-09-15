import AppIntents
import Foundation
import WanderlyCore

/// 让 Siri、快捷指令、操作按钮、Spotlight 都能直接记一件事。
struct CaptureEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "记一件事"
    static let description = IntentDescription("快速记下一件事，AI 会在后台整理归类并提出问题。")
    static let openAppWhenRun = false

    @Parameter(title: "内容", requestValueDialog: "要记什么？")
    var text: String

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let detected = DueParser.parse(text, now: .now)
        EntryActions.capture(text, urgency: .soon, due: detected, in: Persistence.container.mainContext)
        await Reminders.shared.reschedule()
        if let detected {
            let label = DueText.describe(due: detected.date, hasTime: detected.hasTime, now: .now)
            return .result(dialog: "记下了，\(label)截止。AI 会在后台整理。")
        }
        return .result(dialog: "记下了，AI 会在后台整理。")
    }
}

struct WanderlyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureEntryIntent(),
            phrases: ["用\(.applicationName)记一件事", "在\(.applicationName)里速记"],
            shortTitle: "记一件事",
            systemImageName: "square.and.pencil")
        AppShortcut(
            intent: OpenCaptureIntent(),
            phrases: ["打开\(.applicationName)速记"],
            shortTitle: "打开速记",
            systemImageName: "pencil.line")
    }
}
