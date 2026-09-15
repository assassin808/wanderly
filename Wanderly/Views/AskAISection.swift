import SwiftUI
import WanderlyCore

/// AI 只提问，回答由用户自己写，写完追加到「细节」里。
struct AskAISection: View {
    @Bindable var entry: Entry
    @AppStorage(Preferences.Key.aiProvider) private var provider: AIProvider = .gemini
    @State private var questions: [String] = []
    @State private var answers: [String] = []
    @State private var loading = false
    @State private var errorMessage: String?

    var body: some View {
        Section {
            if questions.isEmpty {
                Button {
                    Task { await ask() }
                } label: {
                    HStack {
                        Label(loading ? "正在想问题…" : "让 AI 问几个问题", systemImage: "sparkles")
                        if loading {
                            Spacer()
                            ProgressView()
                        }
                    }
                }
                .disabled(loading)
                .accessibilityIdentifier("askAIButton")
            } else {
                ForEach(questions.indices, id: \.self) { index in
                    VStack(alignment: .leading, spacing: 6) {
                        Text(questions[index])
                            .font(.subheadline.weight(.medium))
                        TextField("有空再答，一两句就行", text: $answers[index], axis: .vertical)
                            .lineLimit(1...5)
                    }
                    .padding(.vertical, 2)
                }
                Button("把回答写进细节", action: apply)
                    .disabled(answers.allSatisfy { $0.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty })
                Button("换一组问题") {
                    Task { await ask() }
                }
                .disabled(loading)
            }
            if let errorMessage {
                Text(errorMessage)
                    .font(.caption)
                    .foregroundStyle(.red)
            }
        } header: {
            Text("AI 追问")
        } footer: {
            Text("AI 只提问，不替你写。")
        }
    }

    private func ask() async {
        guard let apiKey = APIKeyStore.effectiveKey(for: provider) else {
            errorMessage = "先在设置里填 \(provider.displayName) API Key。"
            return
        }
        loading = true
        defer { loading = false }
        do {
            let input = RefinementInput(
                text: entry.text,
                details: entry.details,
                nextStep: entry.nextStep,
                due: DueText.describe(due: entry.due, hasTime: entry.hasTime, now: .now),
                today: Date.now.formatted(date: .complete, time: .omitted))
            let result = try await Refiner.askQuestions(provider: provider, apiKey: apiKey, input: input)
            questions = result
            answers = Array(repeating: "", count: result.count)
            errorMessage = nil
        } catch {
            errorMessage = error.localizedDescription
        }
    }

    private func apply() {
        let pairs = zip(questions, answers)
            .map { ($0, $1.trimmingCharacters(in: .whitespacesAndNewlines)) }
            .filter { !$0.1.isEmpty }
            .map { "问：\($0.0)\n答：\($0.1)" }
        guard !pairs.isEmpty else { return }
        let existing = entry.details.trimmingCharacters(in: .whitespacesAndNewlines)
        entry.details = ([existing] + pairs).filter { !$0.isEmpty }.joined(separator: "\n\n")
        questions = []
        answers = []
    }
}
