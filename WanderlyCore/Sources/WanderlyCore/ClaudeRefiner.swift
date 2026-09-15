import Foundation

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
        case .rateLimited: "请求太频繁了，稍等一会儿再试。"
        case .overloaded: "Claude 暂时繁忙，稍后再试。"
        case .refused: "这条内容 AI 没法追问，可以自己补充。"
        case let .api(status, message): "AI 请求失败（\(status)）\(message.isEmpty ? "" : "：\(message)")"
        case .badResponse: "AI 返回的内容没法解析，再试一次。"
        }
    }
}

/// 调 Claude Messages API，为一条速记生成 1–3 个追问。Swift 没有官方 SDK，这里直接发 HTTP 请求。
public enum ClaudeRefiner {
    public static let model = "claude-opus-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

    static let system = """
    用户匆忙记下了一件事（可能是会议、想法或待办），现在有空来完善它，但原话往往只有几个字。

    找出让这件事能被执行、或者过几天再看还能看懂所缺的最少信息，比如：目的、涉及的人、具体的下一步、时间地点、完成的标准。然后提 1 到 3 个具体的问题，每个问题用一两句话就能回答。已经写清楚的内容不要再问。

    只提问。不替用户下结论，不给建议或方案，不写鼓励或催促的话。用用户记录时用的语言提问。
    """

    public static func makeRequest(apiKey: String, input: RefinementInput) throws -> URLRequest {
        var request = URLRequest(url: endpoint, timeoutInterval: 90)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        request.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // 被安全分类器拒绝时，由服务端自动换推荐的模型重试。
        request.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")

        let body = MessagesRequest(
            model: model,
            maxTokens: 16000,
            fallbacks: "default",
            system: system,
            outputConfig: .init(effort: "low", format: .init(type: "json_schema", schema: QuestionsSchema())),
            messages: [.init(role: "user", content: prompt(for: input))])
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    static func prompt(for input: RefinementInput) -> String {
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

    public static func parse(data: Data, status: Int) throws -> [String] {
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(APIErrorResponse.self, from: data))?.error.message ?? ""
            switch status {
            case 401: throw RefinerError.invalidKey
            case 429: throw RefinerError.rateLimited
            case 500...599: throw RefinerError.overloaded
            default: throw RefinerError.api(status: status, message: message)
            }
        }
        guard let response = try? JSONDecoder().decode(MessagesResponse.self, from: data) else {
            throw RefinerError.badResponse
        }
        if response.stopReason == "refusal" { throw RefinerError.refused }
        guard let text = response.content.first(where: { $0.type == "text" })?.text,
              let decoded = try? JSONDecoder().decode(Questions.self, from: Data(text.utf8)) else {
            throw RefinerError.badResponse
        }
        let questions = decoded.questions
            .map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        guard !questions.isEmpty else { throw RefinerError.badResponse }
        return Array(questions.prefix(3))
    }

    public static func askQuestions(apiKey: String, input: RefinementInput, session: URLSession = .shared) async throws -> [String] {
        let (data, response) = try await session.data(for: makeRequest(apiKey: apiKey, input: input))
        return try parse(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }
}

// MARK: - Wire types

struct MessagesRequest: Encodable {
    struct OutputConfig: Encodable {
        struct Format: Encodable {
            let type: String
            let schema: QuestionsSchema
        }

        let effort: String
        let format: Format
    }

    struct Message: Encodable {
        let role: String
        let content: String
    }

    let model: String
    let maxTokens: Int
    let fallbacks: String
    let system: String
    let outputConfig: OutputConfig
    let messages: [Message]

    enum CodingKeys: String, CodingKey {
        case model, fallbacks, system, messages
        case maxTokens = "max_tokens"
        case outputConfig = "output_config"
    }
}

struct QuestionsSchema: Encodable {
    struct Properties: Encodable {
        let questions = ArraySchema()
    }

    struct ArraySchema: Encodable {
        let type = "array"
        let description = "1 到 3 个具体的问题"
        let items = StringSchema()
    }

    struct StringSchema: Encodable {
        let type = "string"
    }

    let type = "object"
    let properties = Properties()
    let required = ["questions"]
    let additionalProperties = false
}

struct MessagesResponse: Decodable {
    struct Block: Decodable {
        let type: String
        let text: String?
    }

    let stopReason: String?
    let content: [Block]

    enum CodingKeys: String, CodingKey {
        case content
        case stopReason = "stop_reason"
    }
}

struct APIErrorResponse: Decodable {
    struct Detail: Decodable {
        let type: String
        let message: String
    }

    let error: Detail
}

struct Questions: Decodable {
    let questions: [String]
}
