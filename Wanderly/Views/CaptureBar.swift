import SwiftUI
import SwiftData
import WanderlyCore

/// 粘贴或写下一段话，选紧急程度就能记下。截止日期可选，文字里识别到时间会自动带上。
struct CaptureBar: View {
    @Environment(\.modelContext) private var context
    @AppStorage(Preferences.Key.captureUrgency) private var urgency: Urgency = .soon
    @State private var text = ""
    @State private var ignoreDetected = false
    @State private var manualDue: DetectedDue?
    @State private var showDueChooser = false
    @State private var savedCount = 0
    @FocusState private var focused: Bool

    private var canSave: Bool { !text.trimmed.isEmpty }

    /// 用户点掉了识别结果，或者手动选了日期，就不再用识别到的时间。
    private var detected: DetectedDue? {
        guard !ignoreDetected, manualDue == nil else { return nil }
        return DueParser.parse(text, now: .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            TextField("粘贴或写下一段话…", text: $text, axis: .vertical)
                .lineLimit(1...8)
                .focused($focused)
                .accessibilityIdentifier("captureField")

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(Urgency.allCases) { option in
                        Chip(title: option.label, selected: urgency == option) {
                            urgency = option
                        }
                    }
                    Divider()
                        .frame(height: 18)
                    dueChip
                }
            }
            .popover(isPresented: $showDueChooser) {
                DueChooser { due in
                    manualDue = due
                    showDueChooser = false
                }
                .presentationCompactAdaptation(.popover)
            }

            HStack {
                Text(urgency == .archive ? "只让 AI 整理，不会提醒" : "AI 会在后台整理归类、提出问题")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Spacer()
                Button(action: save) {
                    Label("记下", systemImage: "arrow.up")
                }
                .buttonStyle(.borderedProminent)
                .disabled(!canSave)
                .keyboardShortcut(.return, modifiers: .command)
                .accessibilityIdentifier("captureSave")
            }
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.success, trigger: savedCount)
        .onChange(of: text) { _, value in
            if value.isEmpty { ignoreDetected = false }
        }
        .onChange(of: AppRouter.shared.captureRequest) {
            // 等打开着的 sheet 收起来再聚焦，否则键盘弹不出来。
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                focused = true
            }
        }
    }

    @ViewBuilder
    private var dueChip: some View {
        if let detected {
            Chip(title: "识别到 " + DueText.describe(due: detected.date, hasTime: detected.hasTime, now: .now),
                 systemImage: "sparkles", selected: true) {
                ignoreDetected = true
            }
        } else if let manualDue {
            Chip(title: DueText.describe(due: manualDue.date, hasTime: manualDue.hasTime, now: .now),
                 systemImage: "xmark", selected: true) {
                self.manualDue = nil
            }
        } else {
            Chip(title: "截止日期", systemImage: "calendar.badge.plus", selected: false) {
                showDueChooser = true
            }
        }
    }

    private func save() {
        guard canSave else { return }
        EntryActions.capture(text, urgency: urgency, due: manualDue ?? detected, in: context)
        text = ""
        manualDue = nil
        ignoreDetected = false
        focused = false
        savedCount += 1
    }
}

struct Chip: View {
    let title: String
    var systemImage: String?
    let selected: Bool
    let action: () -> Void

    var body: some View {
        Button(action: action) {
            HStack(spacing: 4) {
                if let systemImage { Image(systemName: systemImage) }
                Text(title)
            }
            .font(.subheadline)
            .padding(.horizontal, 10)
            .padding(.vertical, 5)
            .background(selected ? Color.accentColor.opacity(0.18) : Color.secondary.opacity(0.12), in: Capsule())
            .foregroundStyle(selected ? Color.accentColor : Color.primary)
        }
        .buttonStyle(.plain)
    }
}

/// 选截止日期：几个快捷选项，或者日历里挑一天。
struct DueChooser: View {
    let onPick: (DetectedDue) -> Void
    @State private var date = Date.now
    @State private var hasTime = false

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    ForEach(DueShortcut.allCases) { option in
                        Chip(title: option.label(from: .now), selected: false) {
                            onPick(DetectedDue(date: option.date(from: .now), hasTime: false))
                        }
                    }
                }
            }
            DatePicker("截止", selection: $date, displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()
            Toggle("具体时间", isOn: $hasTime)
            Button("设为截止日期") {
                onPick(DetectedDue(date: hasTime ? date : Calendar.current.startOfDay(for: date), hasTime: hasTime))
            }
            .buttonStyle(.borderedProminent)
        }
        .padding()
        .frame(minWidth: 320)
    }
}
