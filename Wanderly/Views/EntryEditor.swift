import SwiftUI
import SwiftData
import WanderlyCore

struct EntryEditor: View {
    @Bindable var entry: Entry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var deleteOnClose = false

    var body: some View {
        NavigationStack {
            Form {
                EntryFields(entry: entry)
                AskAISection(entry: entry)
                Section {
                    if entry.state == .rough {
                        Button("标记为已完善") { entry.state = .open }
                    }
                    if entry.state.isActive {
                        Button("完成") {
                            entry.state = .done
                            dismiss()
                        }
                        Button("推迟到明天") { entry.snooze() }
                        Button("放弃") {
                            entry.state = .dropped
                            dismiss()
                        }
                    } else {
                        Button("恢复为待办") { entry.state = .open }
                    }
                    Button("删除", role: .destructive) {
                        deleteOnClose = true
                        dismiss()
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle(entry.state.label)
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .confirmationAction) {
                    Button("好") { dismiss() }
                }
            }
        }
        .onDisappear {
            if deleteOnClose {
                EntryActions.delete(entry, in: context)
            } else {
                entry.updatedAt = .now
                EntryActions.save(context)
            }
        }
    }
}

/// 编辑和完善共用的字段。
struct EntryFields: View {
    @Bindable var entry: Entry

    var body: some View {
        Section("记下的") {
            TextField("内容", text: $entry.text, axis: .vertical)
                .lineLimit(1...6)
        }
        Section("截止") {
            DueEditor(entry: entry)
        }
        Section("细节") {
            TextField("在哪、和谁、要准备什么、为什么重要…", text: $entry.details, axis: .vertical)
                .lineLimit(3...12)
        }
        Section("下一步") {
            TextField("最小的一步行动", text: $entry.nextStep, axis: .vertical)
                .lineLimit(1...4)
        }
    }
}

struct DueEditor: View {
    @Bindable var entry: Entry

    var body: some View {
        ScrollView(.horizontal, showsIndicators: false) {
            HStack(spacing: 8) {
                ForEach(DueShortcut.allCases) { option in
                    Chip(title: option.label(from: .now),
                         selected: DueShortcut.matching(due: entry.due, hasTime: entry.hasTime, now: .now) == option) {
                        entry.due = option.date(from: .now)
                        entry.hasTime = false
                    }
                }
            }
        }
        Toggle("具体时间", isOn: $entry.hasTime)
            .onChange(of: entry.hasTime) { _, hasTime in
                let calendar = Calendar.current
                if !hasTime {
                    entry.due = calendar.startOfDay(for: entry.due)
                } else if calendar.component(.hour, from: entry.due) == 0 {
                    entry.due = calendar.date(bySettingHour: 9, minute: 0, second: 0, of: entry.due)!
                }
            }
        DatePicker(entry.hasTime ? "时间" : "日期",
                   selection: $entry.due,
                   displayedComponents: entry.hasTime ? [.date, .hourAndMinute] : [.date])
    }
}
