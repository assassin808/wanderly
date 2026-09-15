import SwiftUI
import SwiftData
import WanderlyCore

struct EntryListView: View {
    let entries: [Entry]
    let onOpen: (Entry) -> Void
    @Environment(\.modelContext) private var context
    @State private var showClosed = false

    var body: some View {
        TimelineView(.everyMinute) { timeline in
            list(now: timeline.date)
        }
    }

    private func list(now: Date) -> some View {
        let active = entries.filter { $0.state.isActive }
        let groups = Dictionary(grouping: active) { EntryGroup.of(due: $0.due, hasTime: $0.hasTime, now: now) }
        let closed = entries
            .filter { !$0.state.isActive }
            .sorted { ($0.closedAt ?? .distantPast) > ($1.closedAt ?? .distantPast) }

        return List {
            Section {
                CaptureBar()
            }

            if active.isEmpty {
                Section {
                    ContentUnavailableView("没有待办", systemImage: "leaf", description: Text("想到什么，就在上面记一笔。"))
                }
            }

            ForEach(EntryGroup.allCases, id: \.self) { group in
                if let items = groups[group] {
                    Section {
                        ForEach(items) { entry in
                            row(entry, now: now)
                        }
                    } header: {
                        Text(group.title)
                            .foregroundStyle(group == .overdue ? Color.red : Color.secondary)
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
                    Label("明天", systemImage: "arrow.turn.up.right")
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
                Button("推迟到明天") { EntryActions.snooze(entry, in: context) }
                Button("放弃") { EntryActions.set(entry, to: .dropped, in: context) }
            } else {
                Button("恢复为待办") { EntryActions.set(entry, to: .open, in: context) }
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
        let overdue = active && DueText.isOverdue(due: entry.due, hasTime: entry.hasTime, now: now)

        HStack(alignment: .firstTextBaseline, spacing: 12) {
            Button(action: onToggle) {
                Image(systemName: active ? "circle" : "checkmark.circle.fill")
                    .font(.title3)
                    .foregroundStyle(active ? Color.secondary : Color.green)
            }
            .buttonStyle(.borderless)
            .accessibilityLabel(active ? "完成：\(entry.title)" : "恢复：\(entry.title)")

            VStack(alignment: .leading, spacing: 4) {
                Text(entry.title)
                    .strikethrough(!active)
                    .foregroundStyle(active ? Color.primary : Color.secondary)
                    .lineLimit(2)

                HStack(spacing: 8) {
                    Label(DueText.describe(due: entry.due, hasTime: entry.hasTime, now: now),
                          systemImage: entry.hasTime ? "clock" : "calendar")
                        .foregroundStyle(overdue ? Color.red : Color.secondary)
                    if entry.state == .rough {
                        Text("待完善")
                            .padding(.horizontal, 6)
                            .padding(.vertical, 1)
                            .background(Color.orange.opacity(0.15), in: Capsule())
                            .foregroundStyle(.orange)
                    }
                    if active, !entry.nextStep.isEmpty {
                        Text("→ \(entry.nextStep)")
                            .foregroundStyle(.secondary)
                            .lineLimit(1)
                    }
                }
                .font(.caption)
                .labelStyle(.titleAndIcon)
            }
            Spacer(minLength: 0)
        }
        .padding(.vertical, 2)
    }
}
