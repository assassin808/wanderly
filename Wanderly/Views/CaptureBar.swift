import SwiftUI
import SwiftData
import WanderlyCore

/// 一行输入加几个截止日期按钮。回车就存。
struct CaptureBar: View {
    @Environment(\.modelContext) private var context
    @State private var text = ""
    @State private var shortcut: DueShortcut = .weekend
    @State private var useCustom = false
    @State private var customDate = Date.now
    @State private var customHasTime = false
    @State private var showPicker = false
    @State private var savedCount = 0
    @FocusState private var focused: Bool

    private var canSave: Bool { !text.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                TextField("记一件事…", text: $text)
                    .focused($focused)
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
                    ForEach(DueShortcut.allCases) { option in
                        Chip(title: option.label(from: .now), selected: !useCustom && shortcut == option) {
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
    }

    private func save() {
        guard canSave else { return }
        let due = useCustom
            ? (customHasTime ? customDate : Calendar.current.startOfDay(for: customDate))
            : shortcut.date(from: .now)
        EntryActions.capture(text, due: due, hasTime: useCustom && customHasTime, in: context)
        text = ""
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
