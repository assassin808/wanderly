import Foundation

/// 追问用的模型服务。
public enum AIProvider: String, CaseIterable, Sendable, Identifiable {
    case gemini
    case claude

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gemini: "Gemini"
        case .claude: "Claude"
        }
    }
}

public struct RefinementInput: Sendable, Equatable {
    public var text: String
    public var details: String
    public var nextStep: String
    /// 已经格式化好的截止描述，例如「明天」「周五 15:00」。
    public var due: String
    /// 今天的日期描述，让模型知道时间上下文。
    public var today: String

    public init(text: String, details: String, nextStep: String, due: String, today: String) {
        self.text = text
        self.details = details
        self.nextStep = nextStep
        self.due = due
        self.today = today
    }
}

public enum RefinerError: LocalizedError, Equatable {
    case invalidKey
    case rateLimited
    case overloaded
    case refused
    case api(status: Int, message: String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .invalidKey: "API Key 无效，去设置里检查一下。"
        case .rateLimited: "请求太频繁或额度用完了，稍等一会儿再试。"
        case .overloaded: "AI 服务暂时繁忙，稍后再试。"
        case .refused: "这条内容 AI 没法追问，可以自己补充。"
        case let .api(status, message): "AI 请求失败（\(status)）\(message.isEmpty ? "" : "：\(message)")"
        case .badResponse: "AI 返回的内容没法解析，再试一次。"
        }
    }
}

public enum Refiner {
    public static func askQuestions(provider: AIProvider, apiKey: String, input: RefinementInput, session: URLSession = .shared) async throws -> [String] {
        switch provider {
        case .gemini:
            return try await GeminiRefiner.askQuestions(apiKey: apiKey, input: input, session: session)
        case .claude:
            return try await ClaudeRefiner.askQuestions(apiKey: apiKey, input: input, session: session)
        }
    }
}

/// 两家模型共用的提示词和结果解析。
enum RefinementPrompt {
    static let system = """
    用户匆忙记下了一件事（可能是会议、想法或待办），现在有空来完善它，但原话往往只有几个字。

    找出让这件事能被执行、或者过几天再看还能看懂所缺的最少信息，比如：目的、涉及的人、具体的下一步、时间地点、完成的标准。然后提 1 到 3 个具体的问题，每个问题用一两句话就能回答。已经写清楚的内容不要再问。

    只提问。不替用户下结论，不给建议或方案，不写鼓励或催促的话。用用户记录时用的语言提问。
    """

    static func user(for input: RefinementInput) -> String {
        func field(_ value: String) -> String {
            let trimmed = value.trimmingCharacters(in: .whitespacesAndNewlines)
            return trimmed.isEmpty ? "（还没写）" : trimmed
        }
        return """
        今天：\(input.today)
        截止：\(input.due)
        记下的：\(field(input.text))
        细节：\(field(input.details))
        下一步：\(field(input.nextStep))
        """
    }

    /// 解析 `{"questions": [...]}`，去掉空问题，最多保留 3 个。
    static func questions(fromJSON text: String) throws -> [String] {
        guard let decoded = try? JSONDecoder().decode(Questions.self, from: Data(text.utf8)) else {
            throw RefinerError.badResponse
        }
        let questions = decoded.questions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !questions.isEmpty else { throw RefinerError.badResponse }
        return Array(questions.prefix(3))
    }

    private struct Questions: Decodable {
        let questions: [String]
    }
}
