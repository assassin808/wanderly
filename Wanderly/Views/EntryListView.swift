import SwiftUI
import SwiftData
import WanderlyCore

struct EntryListView: View {
    let entries: [Entry]
    let onOpen: (Entry) -> Void
    @Environment(\.modelContext) private var context
    @Query(sort: \WanderLink.createdAt, order: .reverse) private var links: [WanderLink]
    @AppStorage(Preferences.Key.betaIdeas) private var betaIdeas = false
    @State private var showClosed = false

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            list(now: timeline.date)
        }
    }

    private func list(now: Date) -> some View {
        let active = entries.filter { $0.state.isActive }
        let sections = Dictionary(grouping: active) { ListSection.of($0.snapshot, now: now) }
        let closed = entries
            .filter { !$0.state.isActive }
            .sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }

        return List {
            Section {
                CaptureBar()
            }

            if betaIdeas, !links.isEmpty {
                Section {
                    ForEach(links) { link in
                        WanderCard(link: link)
                    }
                } header: {
                    Text("漫游 · Beta")
                }
            }

            if active.isEmpty {
                Section {
                    ContentUnavailableView("没有待办", systemImage: "leaf", description: Text("想到什么，就在上面记一笔。"))
                }
            }

            ForEach(ListSection.allCases, id: \.self) { section in
                if let items = sections[section] {
                    Section {
                        ForEach(sorted(items)) { entry in
                            row(entry, now: now)
                        }
                    } header: {
                        Text(section.title)
                            .foregroundStyle(section == .attention ? Color.red : Color.secondary)
                    }
                }
            }

            if !closed.isEmpty {
                Section {
                    if showClosed {
                        ForEach(closed.prefix(50)) { entry in
                            row(entry, now: now)
                        }
                    }
                } header: {
                    Button {
                        withAnimation { showClosed.toggle() }
                    } label: {
                        HStack(spacing: 4) {
                            Text("已结束 \(closed.count)")
                            Image(systemName: showClosed ? "chevron.down" : "chevron.right")
                        }
                    }
                    .buttonStyle(.plain)
                }
            }
        }
        .scrollDismissesKeyboard(.immediately)
    }

    /// 待完善的在前，有截止的按时间，其余新记的在前。
    private func sorted(_ items: [Entry]) -> [Entry] {
        items.sorted {
            ($0.state == .rough ? 0 : 1, $0.hasDue ? $0.due : .distantFuture, -$0.createdAt.timeIntervalSince1970)
                < ($1.state == .rough ? 0 : 1, $1.hasDue ? $1.due : .distantFuture, -$1.createdAt.timeIntervalSince1970)
        }
    }

    private func row(_ entry: Entry, now: Date) -> some View {
        EntryRow(entry: entry, now: now) {
            EntryActions.set(entry, to: entry.state.isActive ? .done : .open, in: context)
        }
        .contentShape(Rectangle())
        .onTapGesture { onOpen(entry) }
        .swipeActions(edge: .leading, allowsFullSwipe: true) {
            if entry.state.isActive {
                Button {
                    EntryActions.set(entry, to: .done, in: context)
                } label: {
                    Label("完成", systemImage: "checkmark")
                }
                .tint(.green)
            }
        }
        .swipeActions(edge: .trailing) {
            if entry.state.isActive {
                Button {
                    EntryActions.set(entry, to: .dropped, in: context)
                } label: {
                    Label("放弃", systemImage: "xmark")
                }
                .tint(.gray)
                Button {
                    EntryActions.snooze(entry, in: context)
                } label: {
                    Label("明天", systemImage: "moon")
                }
                .tint(.orange)
            } else {
                Button(role: .destructive) {
                    EntryActions.delete(entry, in: context)
                } label: {
                    Label("删除", systemImage: "trash")
                }
            }
        }
        .contextMenu {
            if entry.state.isActive {
                Button("完成") { EntryActions.set(entry, to: .done, in: context) }
                Button(entry.hasDue ? "推迟到明天" : "明天再提醒") { EntryActions.snooze(entry, in: context) }
                Button("放弃") { EntryActions.set(entry, to: .dropped, in: context) }
            } else {
                Button("恢复") { EntryActions.set(entry, to: .open, in: context) }
            }
            Divider()
            Button("删除", role: .destructive) { EntryActions.delete(entry, in: context) }
        }
    }
}

struct EntryRow: View {
    let entry: Entry
    let now: Date
    let onToggle: () -> Void

    var body: some View {
        let active = entry.state.isActive
        let overdue = active && entry.hasDue && DueText.isOverdue(due: entry.due, hasTime: entry.hasTime, now: now)

        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: active ? "circle" : "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(active ? Color.secondary : Color.green)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(active ? "完成：\(entry.title)" : "恢复：\(entry.title)")

            VStack(alignment: .leading, spacing: 4) {
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let category = entry.category {
                        Image(systemName: category.systemImage)
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Text(entry.title)
                        .strikethrough(!active)
                        .foregroundStyle(active ? Color.primary : Color.secondary)
                        .lineLimit(2)
                        // AI 整理完会换标题，用原文第一行做固定标识，方便 UI 测试找到这一行。
                        .accessibilityIdentifier("entry:\(entry.firstLine)")
                }

                // AI 换了标题时，下面仍然显示自己记下的原文。
                if entry.text.trimmed != entry.title {
                    Text(entry.text)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(2)
                }

                HStack(spacing: 8) {
                    if let dueLabel = entry.dueLabel {
                        Label(dueLabel, systemImage: entry.hasTime ? "clock" : "calendar")
                            .foregroundStyle(overdue ? Color.red : Color.secondary)
                    }
                    if active {
                        status
                    }
                }
                .font(.caption)
                .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }

    @ViewBuilder
    private var status: some View {
        if AIWorker.shared.replying.contains(entry.id) {
            Label("AI 正在回复", systemImage: "ellipsis.bubble")
                .foregroundStyle(.secondary)
        } else if entry.aiStatus == .failed {
            Label("AI 整理失败", systemImage: "exclamationmark.triangle")
                .foregroundStyle(.orange)
        } else if entry.aiStatus != .done, AIWorker.shared.isEnabled {
            Label("AI 整理中", systemImage: "sparkles")
                .foregroundStyle(.secondary)
        } else if entry.pendingQuestion != nil {
            Tag(text: entry.pendingQuestion?.kind == .water ? "AI 有个新问题" : "AI 有问题问你")
        } else if entry.state == .rough {
            Tag(text: "待完善")
        }
    }
}

private struct Tag: View {
    let text: String

    var body: some View {
        Text(text)
            .padding(.horizontal, 6)
            .padding(.vertical, 1)
            .background(Color.orange.opacity(0.15), in: Capsule())
            .foregroundStyle(.orange)
    }
}

/// Beta 漫游的结果卡片。
struct WanderCard: View {
    let link: WanderLink
    @Environment(\.modelContext) private var context

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(link.title, systemImage: "point.3.connected.trianglepath.dotted")
                .font(.headline)
            Text(link.insight)
                .font(.subheadline)
            if !link.question.isEmpty {
                Text(link.question)
                    .font(.subheadline)
                    .foregroundStyle(.secondary)
            }
            Text("来自：\(link.sourceTitles) · 这是推测")
                .font(.caption)
                .foregroundStyle(.secondary)
            HStack {
                Button("采纳为新想法") { EntryActions.accept(link, in: context) }
                    .buttonStyle(.bordered)
                Button("删掉", role: .destructive) {
                    context.delete(link)
                    try? context.save()
                }
                .buttonStyle(.borderless)
            }
        }
        .padding(.vertical, 4)
    }
}
