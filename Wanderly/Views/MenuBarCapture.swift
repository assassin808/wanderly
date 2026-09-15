#if os(macOS)
import AppKit
import SwiftUI
import SwiftData
import WanderlyCore

/// Mac 菜单栏里的记录窗口。
struct MenuBarCapture: View {
    @Environment(\.openWindow) private var openWindow
    @Query(sort: \Entry.due) private var entries: [Entry]

    var body: some View {
        let now = Date.now
        let soon = entries
            .filter { $0.state.isActive && ListSection.of($0.snapshot, now: now) <= .urgent }
            .prefix(8)

        VStack(alignment: .leading, spacing: 12) {
            CaptureBar()

            Divider()

            if soon.isEmpty {
                Text("没有逾期、今天到期或紧急的事")
                    .foregroundStyle(.secondary)
            } else {
                ForEach(soon) { entry in
                    HStack {
                        Text(entry.title)
                            .lineLimit(1)
                        Spacer()
                        Text(entry.dueLabel ?? entry.urgency.label)
                            .foregroundStyle(entry.hasDue && DueText.isOverdue(due: entry.due, hasTime: entry.hasTime, now: now) ? Color.red : Color.secondary)
                    }
                    .font(.callout)
                }
            }

            Divider()

            HStack {
                Button("打开 Wanderly") {
                    NSApp.activate()
                    openWindow(id: "main")
                }
                Spacer()
                Button("退出") { NSApp.terminate(nil) }
            }
        }
        .padding(14)
        .frame(width: 360)
    }
}
#endif
