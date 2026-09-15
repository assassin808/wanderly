import SwiftUI
import WidgetKit
import WanderlyCore

enum WidgetPalette {
    static let green = Color(red: 0.24, green: 0.46, blue: 0.36)
    static let orange = Color(red: 0.94, green: 0.61, blue: 0.35)
}

enum WidgetLinks {
    static let capture = URL(string: "wanderly://capture")!

    static func entry(_ id: UUID) -> URL {
        URL(string: "wanderly://entry/\(id.uuidString)")!
    }
}

/// 小组件的界面。App 调试时也用它来渲染预览图，所以不依赖 TimelineEntry。
struct TodayWidgetView: View {
    let snapshot: WidgetSnapshot
    let date: Date
    let family: WidgetFamily

    var body: some View {
        switch family {
        #if os(iOS)
        case .accessoryInline:
            inline
        case .accessoryCircular:
            circular
        case .accessoryRectangular:
            rectangular
        #endif
        case .systemMedium:
            medium
        default:
            small
        }
    }

    private var small: some View {
        let focus = snapshot.focus(at: date, limit: 3)
        return VStack(alignment: .leading, spacing: 6) {
            HStack(alignment: .firstTextBaseline) {
                Text(focus.heading)
                    .font(.headline)
                    .foregroundStyle(WidgetPalette.green)
                Spacer()
                if focus.urgentCount > 0 {
                    Text("\(focus.urgentCount)")
                        .font(.headline.monospacedDigit())
                        .foregroundStyle(WidgetPalette.orange)
                }
            }
            if focus.items.isEmpty {
                Text("想到什么，点这里记一笔")
                    .font(.caption)
                    .foregroundStyle(.secondary)
            } else {
                ForEach(focus.items) { item in
                    row(item, compact: true)
                }
            }
            Spacer(minLength: 0)
            HStack {
                Spacer()
                Image(systemName: "square.and.pencil")
                    .font(.title3)
                    .foregroundStyle(WidgetPalette.green)
            }
        }
        .widgetURL(WidgetLinks.capture)
    }

    private var medium: some View {
        let focus = snapshot.focus(at: date, limit: 4)
        let count = focus.urgentCount > 0 ? focus.urgentCount : snapshot.items.count
        return HStack(alignment: .top, spacing: 14) {
            VStack(alignment: .leading, spacing: 2) {
                Text(focus.heading)
                    .font(.headline)
                    .foregroundStyle(WidgetPalette.green)
                Text("\(count)")
                    .font(.system(size: 40, weight: .semibold, design: .rounded))
                    .foregroundStyle(focus.urgentCount > 0 ? WidgetPalette.orange : Color.secondary)
                Text(focus.urgentCount > 0 ? "件要处理" : "件待办")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                if snapshot.roughCount > 0 {
                    Text("\(snapshot.roughCount) 条待完善")
                        .font(.caption2)
                        .foregroundStyle(WidgetPalette.orange)
                }
                Spacer(minLength: 0)
                Link(destination: WidgetLinks.capture) {
                    Label("记一件事", systemImage: "square.and.pencil")
                        .font(.caption.weight(.medium))
                        .foregroundStyle(WidgetPalette.green)
                }
            }
            .frame(width: 96, alignment: .leading)

            VStack(alignment: .leading, spacing: 8) {
                if focus.items.isEmpty {
                    Text("没有待办。想到什么就记下来。")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                } else {
                    ForEach(focus.items) { item in
                        Link(destination: WidgetLinks.entry(item.id)) {
                            row(item, compact: false)
                        }
                    }
                }
                Spacer(minLength: 0)
            }
            .frame(maxWidth: .infinity, alignment: .leading)
        }
    }

    #if os(iOS)
    private var rectangular: some View {
        let focus = snapshot.focus(at: date, limit: 2)
        return VStack(alignment: .leading, spacing: 1) {
            Text(focus.urgentCount > 0 ? "今天 \(focus.urgentCount) 件" : "Wanderly")
                .font(.headline)
                .widgetAccentable()
            if focus.items.isEmpty {
                Text("点一下记一件事")
                    .font(.caption)
            }
            ForEach(focus.items) { item in
                Text("\(DueText.describe(due: item.due, hasTime: item.hasTime, now: date)) \(item.title)")
                    .font(.caption)
                    .lineLimit(1)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .widgetURL(WidgetLinks.capture)
    }

    private var circular: some View {
        let count = snapshot.focus(at: date, limit: 0).urgentCount
        return ZStack {
            AccessoryWidgetBackground()
            VStack(spacing: 0) {
                Image(systemName: "square.and.pencil")
                    .font(.caption)
                Text("\(count)")
                    .font(.title3.weight(.semibold).monospacedDigit())
            }
        }
        .widgetURL(WidgetLinks.capture)
    }

    @ViewBuilder
    private var inline: some View {
        let focus = snapshot.focus(at: date, limit: 1)
        if let first = focus.items.first, focus.urgentCount > 0 {
            Text("今天 \(focus.urgentCount) 件 · \(first.title)")
        } else {
            Text("Wanderly：今天没有到期的事")
        }
    }
    #endif

    private func row(_ item: WidgetSnapshot.Item, compact: Bool) -> some View {
        let overdue = DueText.isOverdue(due: item.due, hasTime: item.hasTime, now: date)
        return VStack(alignment: .leading, spacing: 1) {
            // 用具体颜色：外层 Link 的强调色会盖掉层级样式 .primary，标题会变成蓝色。
            Text(item.title)
                .font(compact ? .caption.weight(.medium) : .subheadline)
                .foregroundStyle(Color.primary)
                .lineLimit(1)
            Text(DueText.describe(due: item.due, hasTime: item.hasTime, now: date) + (item.isRough ? " · 待完善" : ""))
                .font(.caption2)
                .foregroundStyle(overdue ? Color.red : Color.secondary)
                .lineLimit(1)
        }
    }
}

extension WidgetSnapshot {
    /// 小组件库里的预览和调试渲染用的示例数据。
    static var sample: WidgetSnapshot {
        let calendar = Calendar.current
        let today = calendar.startOfDay(for: .now)
        return WidgetSnapshot(items: [
            Item(id: UUID(), title: "报销会议差旅", due: calendar.date(byAdding: .day, value: -2, to: today)!, hasTime: false, isRough: false),
            Item(id: UUID(), title: "和导师开组会", due: calendar.date(bySettingHour: 15, minute: 0, second: 0, of: today)!, hasTime: true, isRough: false),
            Item(id: UUID(), title: "回房东邮件 暖气", due: today, hasTime: false, isRough: true),
        ], roughCount: 1)
    }
}
