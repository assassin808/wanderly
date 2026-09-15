import Foundation

/// 调 Claude Messages API。Swift 没有官方 SDK，这里直接发 HTTP 请求。
public enum ClaudeRefiner {
    public static let model = "claude-opus-5"
    static let endpoint = URL(string: "https://api.anthropic.com/v1/messages")!

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
            system: RefinementPrompt.system,
            outputConfig: .init(effort: "low", format: .init(type: "json_schema", schema: QuestionsSchema())),
            messages: [.init(role: "user", content: RefinementPrompt.user(for: input))])
        request.httpBody = try JSONEncoder().encode(body)
        return request
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
        guard let text = response.content.first(where: { $0.type == "text" })?.text else {
            throw RefinerError.badResponse
        }
        return try RefinementPrompt.questions(fromJSON: text)
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
