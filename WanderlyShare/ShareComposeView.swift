import SwiftUI
import WanderlyCore

struct ShareComposeView: View {
    @Bindable var model: ShareModel
    let onDone: () -> Void
    let onCancel: () -> Void
    @State private var urgency: Urgency = .soon
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
                    Picker("紧急程度", selection: $urgency) {
                        ForEach(Urgency.allCases) { option in
                            Text(option.label).tag(option)
                        }
                    }
                    .pickerStyle(.segmented)
                    if let detected {
                        Toggle("截止：\(DueText.describe(due: detected.date, hasTime: detected.hasTime, now: .now))", isOn: $useDetected)
                    }
                } header: {
                    Text("多紧急")
                } footer: {
                    Text("打开 Wanderly 时，AI 会整理归类、提出问题，并排好提醒。")
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
        do {
            try model.save(urgency: urgency, due: useDetected ? detected : nil)
            onDone()
        } catch {
            errorMessage = "没能存下：\(error.localizedDescription)"
        }
    }
}
