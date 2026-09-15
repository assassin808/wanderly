import SwiftUI
import SwiftData
import WanderlyCore

/// 一行输入加几个截止日期按钮。回车就存；能从输入里识别出时间时优先用识别到的。
struct CaptureBar: View {
    @Environment(\.modelContext) private var context
    @State private var text = ""
    @State private var shortcut: DueShortcut = .weekend
    @State private var useCustom = false
    @State private var customDate = Date.now
    @State private var customHasTime = false
    @State private var showPicker = false
    @State private var ignoreDetected = false
    @State private var savedCount = 0
    @FocusState private var focused: Bool

    private var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    /// 用户点掉了识别结果，或者手动选了日期，就不再用识别到的时间。
    private var detected: DetectedDue? {
        guard !ignoreDetected, !useCustom else { return nil }
        return DueParser.parse(text, now: .now)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("记一件事…", text: $text)
                    .focused($focused)
                    .accessibilityIdentifier("captureField")
                    .submitLabel(.done)
                    .onSubmit(save)
                Button(action: save) {
                    Image(systemName: "arrow.up.circle.fill")
                        .font(.title2)
                }
                .buttonStyle(.borderless)
                .disabled(!canSave)
            }

            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 8) {
                    if let detected {
                        Chip(title: "识别到 " + DueText.describe(due: detected.date, hasTime: detected.hasTime, now: .now),
                             systemImage: "sparkles", selected: true) {
                            ignoreDetected = true
                        }
                    }
                    ForEach(DueShortcut.allCases) { option in
                        Chip(title: option.label(from: .now), selected: detected == nil && !useCustom && shortcut == option) {
                            ignoreDetected = true
                            useCustom = false
                            shortcut = option
                        }
                    }
                    Chip(title: useCustom ? DueText.describe(due: customDate, hasTime: customHasTime, now: .now) : "选日期",
                         systemImage: "calendar", selected: useCustom) {
                        useCustom = true
                        showPicker = true
                    }
                    .popover(isPresented: $showPicker) {
                        DuePicker(date: $customDate, hasTime: $customHasTime)
                            .presentationCompactAdaptation(.popover)
                    }
                }
            }
        }
        .padding(.vertical, 4)
        .sensoryFeedback(.success, trigger: savedCount)
        .onChange(of: AppRouter.shared.captureRequest) {
            // 等打开着的 sheet 收起来再聚焦，否则键盘弹不出来。
            Task {
                try? await Task.sleep(for: .milliseconds(400))
                focused = true
            }
        }
    }

    private func save() {
        guard canSave else { return }
        let due: Date
        let hasTime: Bool
        if let detected {
            due = detected.date
            hasTime = detected.hasTime
        } else if useCustom {
            due = customHasTime ? customDate : Calendar.current.startOfDay(for: customDate)
            hasTime = customHasTime
        } else {
            due = shortcut.date(from: .now)
            hasTime = false
        }
        EntryActions.capture(text, due: due, hasTime: hasTime, in: context)
        text = ""
        ignoreDetected = false
        savedCount += 1
        focused = true
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

struct DuePicker: View {
    @Binding var date: Date
    @Binding var hasTime: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            DatePicker("截止", selection: $date, displayedComponents: hasTime ? [.date, .hourAndMinute] : [.date])
                .datePickerStyle(.graphical)
                .labelsHidden()
            Toggle("具体时间", isOn: $hasTime)
        }
        .padding()
        .frame(minWidth: 320)
    }
}
