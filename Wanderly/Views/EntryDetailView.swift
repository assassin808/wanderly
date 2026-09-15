import SwiftUI
import SwiftData
import WanderlyCore

/// 一条记录的详情：标题、紧急程度、截止、原文、AI 整理，以及和 AI 的对话。
struct EntryDetailView: View {
    @Bindable var entry: Entry
    @Environment(\.dismiss) private var dismiss
    @Environment(\.modelContext) private var context
    @State private var deleteOnClose = false

    var body: some View {
        NavigationStack {
            EntryConversation(entry: entry)
                .navigationTitle(entry.category?.label ?? "记录")
                #if os(iOS)
                .navigationBarTitleDisplayMode(.inline)
                #endif
                .toolbar {
                    ToolbarItem(placement: .primaryAction) {
                        Menu {
                            ShareLink(item: entry.markdown, preview: SharePreview(entry.title)) {
                                Label("导出为 Markdown", systemImage: "square.and.arrow.up")
                            }
                            if entry.state == .rough {
                                Button("完善好了", systemImage: "checkmark.seal") {
                                    EntryActions.set(entry, to: .open, in: context)
                                }
                            }
                            if entry.state.isActive {
                                Button("完成", systemImage: "checkmark") {
                                    EntryActions.set(entry, to: .done, in: context)
                                    dismiss()
                                }
                                Button(entry.hasDue ? "推迟到明天" : "明天再提醒", systemImage: "moon") {
                                    EntryActions.snooze(entry, in: context)
                                }
                                Button("放弃", systemImage: "xmark") {
                                    EntryActions.set(entry, to: .dropped, in: context)
                                    dismiss()
                                }
                            } else {
                                Button("恢复", systemImage: "arrow.uturn.backward") {
                                    EntryActions.set(entry, to: .open, in: context)
                                }
                            }
                            Button("删除", systemImage: "trash", role: .destructive) {
                                deleteOnClose = true
                                dismiss()
                            }
                        } label: {
                            Label("更多", systemImage: "ellipsis.circle")
                        }
                        .accessibilityIdentifier("entryMenu")
                    }
                    ToolbarItem(placement: .confirmationAction) {
                        Button("好") { dismiss() }
                    }
                }
        }
        .onDisappear {
            if deleteOnClose {
                EntryActions.delete(entry, in: context)
            } else {
                EntryActions.save(context)
            }
        }
    }
}

/// 详情和完善流程共用：可编辑的记录内容加对话。
struct EntryConversation: View {
    @Bindable var entry: Entry
    @Environment(\.modelContext) private var context
    @State private var draft = ""
    @State private var showOriginal = false
    @FocusState private var inputFocused: Bool

    private var worker: AIWorker { AIWorker.shared }

    var body: some View {
        ScrollViewReader { proxy in
            List {
                Section {
                    // 标题为空时占位显示原文第一行；绑定 aiTitle 本身，删空时不会被第一行填回来。
                    TextField(entry.firstLine, text: titleBinding, axis: .vertical)
                        .font(.title3.weight(.semibold))
                    Picker("紧急程度", selection: urgencyBinding) {
                        ForEach(Urgency.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    Picker("类别", selection: categoryBinding) {
                        ForEach(EntryCategory.allCases) { option in
                            Label(option.label, systemImage: option.systemImage).tag(option)
                        }
                    }
                }

                Section("截止") {
                    DueEditor(entry: entry)
                }

                Section {
                    DisclosureGroup(isExpanded: $showOriginal) {
                        TextField("原文", text: $entry.text, axis: .vertical)
                            .lineLimit(2...20)
                    } label: {
                        VStack(alignment: .leading, spacing: 2) {
                            Text("原文")
                            if !showOriginal {
                                Text(entry.text)
                                    .font(.caption)
                                    .foregroundStyle(.secondary)
                                    .lineLimit(2)
                            }
                        }
                    }
                }

                // 旧版本把补充内容存在 details 和 nextStep 里，有内容才显示，AI 和导出也会带上。
                if !entry.details.isEmpty || !entry.nextStep.isEmpty {
                    Section {
                        if !entry.details.isEmpty {
                            TextField("细节", text: $entry.details, axis: .vertical)
                                .lineLimit(1...12)
                        }
                        if !entry.nextStep.isEmpty {
                            TextField("下一步", text: $entry.nextStep, axis: .vertical)
                                .lineLimit(1...4)
                        }
                    } header: {
                        Text("之前记的细节")
                    }
                }

                aiSection

                Section("对话") {
                    ForEach(entry.sortedMessages) { message in
                        MessageBubble(message: message)
                            .listRowSeparator(.hidden)
                    }
                    if worker.replying.contains(entry.id) {
                        HStack(spacing: 8) {
                            ProgressView()
                            Text("AI 正在想…")
                                .foregroundStyle(.secondary)
                        }
                        .listRowSeparator(.hidden)
                    } else if !entry.replyError.isEmpty {
                        VStack(alignment: .leading, spacing: 6) {
                            Label(entry.replyError, systemImage: "exclamationmark.triangle")
                                .foregroundStyle(.orange)
                            Button("重试") { worker.retryReply(entry) }
                        }
                    }
                    if entry.sortedMessages.isEmpty {
                        Text(entry.category == .idea ? "想到什么都可以和 AI 聊，它会陪你把想法想深一点。" : "有需要可以问 AI，比如怎么拆成下一步。")
                            .font(.caption)
                            .foregroundStyle(.secondary)
                    }
                    Color.clear
                        .frame(height: 1)
                        .id("bottom")
                        .listRowSeparator(.hidden)
                }
            }
            .safeAreaInset(edge: .bottom) {
                inputBar
            }
            .onChange(of: entry.messages?.count) {
                withAnimation { proxy.scrollTo("bottom", anchor: .bottom) }
            }
        }
    }

    @ViewBuilder
    private var aiSection: some View {
        switch entry.aiStatus {
        case .pending, .processing:
            if worker.isEnabled {
                Section {
                    HStack(spacing: 8) {
                        if entry.aiError.isEmpty {
                            ProgressView()
                            Text("AI 正在整理…")
                        } else {
                            Label(entry.aiError, systemImage: "key")
                        }
                    }
                    .foregroundStyle(.secondary)
                }
            }
        case .failed:
            Section {
                Label(entry.aiError, systemImage: "exclamationmark.triangle")
                    .foregroundStyle(.orange)
                Button("重新整理") { worker.retryOrganize(entry) }
            }
        case .done:
            if !entry.aiSummary.isEmpty {
                Section("AI 整理") {
                    Text(entry.aiSummary)
                        .textSelection(.enabled)
                }
            }
        }
    }

    private var inputBar: some View {
        HStack(alignment: .bottom, spacing: 8) {
            TextField(entry.pendingQuestion != nil ? "回答 AI 的问题…" : "和 AI 聊聊这件事…", text: $draft, axis: .vertical)
                .lineLimit(1...5)
                .focused($inputFocused)
                .padding(.horizontal, 12)
                .padding(.vertical, 8)
                .background(Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 18))
                .accessibilityIdentifier("chatField")
                .onSubmit(send)
            Button(action: send) {
                Image(systemName: "arrow.up.circle.fill")
                    .font(.title)
            }
            .buttonStyle(.borderless)
            .disabled(draft.trimmed.isEmpty)
            .accessibilityIdentifier("chatSend")
        }
        .padding(.horizontal)
        .padding(.vertical, 8)
        .background(.bar)
    }

    private func send() {
        let text = draft.trimmed
        guard !text.isEmpty else { return }
        draft = ""
        worker.send(text, to: entry)
    }

    private var titleBinding: Binding<String> {
        Binding {
            entry.aiTitle
        } set: { value in
            entry.aiTitle = value
            entry.touch()
        }
    }

    private var urgencyBinding: Binding<Urgency> {
        Binding {
            entry.urgency
        } set: { value in
            entry.urgency = value
            entry.touch()
        }
    }

    private var categoryBinding: Binding<EntryCategory> {
        Binding {
            entry.category ?? .other
        } set: { value in
            entry.category = value
        }
    }
}

struct MessageBubble: View {
    let message: ChatMessage

    var body: some View {
        let mine = message.role == .user
        HStack {
            if mine { Spacer(minLength: 40) }
            VStack(alignment: .leading, spacing: 4) {
                if message.kind != .chat {
                    Text(message.kind == .water ? "浇水" : "AI 追问")
                        .font(.caption2.weight(.semibold))
                        .foregroundStyle(.orange)
                }
                Text(message.text)
                    .textSelection(.enabled)
            }
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .background(mine ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12), in: RoundedRectangle(cornerRadius: 14))
            if !mine { Spacer(minLength: 40) }
        }
        .accessibilityElement(children: .combine)
        .accessibilityIdentifier(mine ? "userMessage" : "aiMessage")
    }
}

/// 截止日期是可选的。
struct DueEditor: View {
    @Bindable var entry: Entry

    var body: some View {
        Toggle("有截止日期", isOn: $entry.hasDue)
            .onChange(of: entry.hasDue) { _, hasDue in
                if hasDue, entry.due < Calendar.current.startOfDay(for: .now) {
                    entry.due = DueShortcut.tomorrow.date(from: .now)
                    entry.hasTime = false
                }
                entry.touch()
            }
        if entry.hasDue {
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
}
