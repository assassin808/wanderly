import AppIntents
import Foundation
import WanderlyCore

/// 让 Siri、快捷指令、操作按钮、Spotlight 都能直接速记。
struct CaptureEntryIntent: AppIntent {
    static let title: LocalizedStringResource = "记一件事"
    static let description = IntentDescription("快速记下一件事，默认本周末截止，晚上会提醒你完善。")
    static let openAppWhenRun = false

    @Parameter(title: "内容", requestValueDialog: "要记什么？")
    var text: String

    @Parameter(title: "截止日期")
    var due: Date?

    @MainActor
    func perform() async throws -> some IntentResult & ProvidesDialog {
        let date = due.map { Calendar.current.startOfDay(for: $0) } ?? DueShortcut.weekend.date(from: .now)
        EntryActions.capture(text, due: date, hasTime: false, in: Persistence.container.mainContext)
        await Reminders.shared.reschedule()
        let label = DueText.describe(due: date, hasTime: false, now: .now)
        return .result(dialog: "记下了，\(label)截止")
    }
}

struct WanderlyShortcuts: AppShortcutsProvider {
    static var appShortcuts: [AppShortcut] {
        AppShortcut(
            intent: CaptureEntryIntent(),
            phrases: ["用\(.applicationName)记一件事", "在\(.applicationName)里速记"],
            shortTitle: "记一件事",
            systemImageName: "square.and.pencil")
    }
}
