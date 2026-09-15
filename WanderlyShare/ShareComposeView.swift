import SwiftUI
import WanderlyCore

struct ShareComposeView: View {
    @Bindable var model: ShareModel
    let onDone: () -> Void
    let onCancel: () -> Void
    @State private var shortcut: DueShortcut = .weekend
    @State private var useDetected = true
    @State private var errorMessage: String?

    private var detected: DetectedDue? { DueParser.parse(model.text, now: .now) }
    private var trimmed: String { model.text.trimmingCharacters(in: .whitespacesAndNewlines) }

    var body: some View {
        NavigationStack {
            Form {
                Section("记下的") {
                    if model.loading {
                        ProgressView()
                    }
                    TextField("要记住什么？", text: $model.text, axis: .vertical)
                        .lineLimit(3...10)
                }
                Section {
                    if let detected {
                        Toggle("识别到 \(DueText.describe(due: detected.date, hasTime: detected.hasTime, now: .now))", isOn: $useDetected)
                    }
                    Picker("截止", selection: $shortcut) {
                        ForEach(DueShortcut.allCases) { option in
                            Text(option.label(from: .now)).tag(option)
                        }
                    }
                    .disabled(detected != nil && useDetected)
                } header: {
                    Text("截止")
                } footer: {
                    Text("打开 Wanderly 时会加进列表，并排好提醒。")
                }
                if let errorMessage {
                    Section {
                        Text(errorMessage)
                            .foregroundStyle(.red)
                    }
                }
            }
            .formStyle(.grouped)
            .navigationTitle("存到 Wanderly")
            #if os(iOS)
            .navigationBarTitleDisplayMode(.inline)
            #endif
            .toolbar {
                ToolbarItem(placement: .cancellationAction) {
                    Button("取消", action: onCancel)
                }
                ToolbarItem(placement: .confirmationAction) {
                    Button("记下", action: save)
                        .disabled(model.loading || trimmed.isEmpty)
                }
            }
        }
    }

    private func save() {
        let chosen = useDetected ? detected : nil
        do {
            try model.save(due: chosen?.date ?? shortcut.date(from: .now), hasTime: chosen?.hasTime ?? false)
            onDone()
        } catch {
            errorMessage = "没能存下：\(error.localizedDescription)"
        }
    }
}
