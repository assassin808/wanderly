import Foundation

/// 调 Gemini generateContent 接口，用 responseSchema 约束成 JSON。
public enum GeminiRefiner {
    /// 免费额度下单个模型经常繁忙或限流，按顺序换着试。
    public static let models = ["gemini-flash-latest", "gemini-flash-lite-latest"]

    static func endpoint(model: String) -> URL {
        URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!
    }

    public static func makeRequest(apiKey: String, input: RefinementInput, model: String = models[0]) throws -> URLRequest {
        var request = URLRequest(url: endpoint(model: model), timeoutInterval: 60)
        request.httpMethod = "POST"
        request.setValue("application/json", forHTTPHeaderField: "content-type")
        request.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        let body = GenerateContentRequest(
            systemInstruction: .init(parts: [.init(text: RefinementPrompt.system)]),
            contents: [.init(role: "user", parts: [.init(text: RefinementPrompt.user(for: input))])],
            generationConfig: .init(
                responseMimeType: "application/json",
                responseSchema: GeminiQuestionsSchema(),
                thinkingConfig: .init(thinkingLevel: "low")))
        request.httpBody = try JSONEncoder().encode(body)
        return request
    }

    public static func parse(data: Data, status: Int) throws -> [String] {
        guard (200..<300).contains(status) else {
            let detail = (try? JSONDecoder().decode(GeminiErrorResponse.self, from: data))?.error
            let message = detail?.message ?? ""
            switch status {
            case 400 where message.localizedCaseInsensitiveContains("API key"):
                throw RefinerError.invalidKey
            case 401, 403:
                throw RefinerError.invalidKey
            case 429:
                throw RefinerError.rateLimited
            case 500...599:
                throw RefinerError.overloaded
            default:
                throw RefinerError.api(status: status, message: message)
            }
        }
        guard let response = try? JSONDecoder().decode(GenerateContentResponse.self, from: data) else {
            throw RefinerError.badResponse
        }
        if response.promptFeedback?.blockReason != nil { throw RefinerError.refused }
        guard let candidate = response.candidates?.first else { throw RefinerError.badResponse }
        if let reason = candidate.finishReason, ["SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII"].contains(reason) {
            throw RefinerError.refused
        }
        let text = (candidate.content?.parts ?? [])
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined()
        return try RefinementPrompt.questions(fromJSON: text)
    }

    public static func askQuestions(apiKey: String, input: RefinementInput, session: URLSession = .shared) async throws -> [String] {
        var lastError = RefinerError.overloaded
        for model in models {
            let (data, response) = try await session.data(for: makeRequest(apiKey: apiKey, input: input, model: model))
            do {
                return try parse(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
            } catch let error as RefinerError where error.triesNextModel {
                lastError = error
            }
        }
        throw lastError
    }
}

extension RefinerError {
    /// 繁忙、限流或模型不存在时换下一个模型；Key 无效等错误直接返回。
    var triesNextModel: Bool {
        switch self {
        case .overloaded, .rateLimited: true
        case let .api(status, _): status == 404
        default: false
        }
    }
}

// MARK: - Wire types

struct GenerateContentRequest: Encodable {
    struct Content: Encodable {
        var role: String? = nil
        let parts: [Part]
    }

    struct Part: Encodable {
        let text: String
    }

    struct GenerationConfig: Encodable {
        let responseMimeType: String
        let responseSchema: GeminiQuestionsSchema
        let thinkingConfig: ThinkingConfig
    }

    struct ThinkingConfig: Encodable {
        let thinkingLevel: String
    }

    let systemInstruction: Content
    let contents: [Content]
    let generationConfig: GenerationConfig
}

struct GeminiQuestionsSchema: Encodable {
    struct Properties: Encodable {
        let questions = ArraySchema()
    }

    struct ArraySchema: Encodable {
        let type = "ARRAY"
        let description = "1 到 3 个具体的问题"
        let items = StringSchema()
    }

    struct StringSchema: Encodable {
        let type = "STRING"
    }

    let type = "OBJECT"
    let properties = Properties()
    let required = ["questions"]
}

struct GenerateContentResponse: Decodable {
    struct Candidate: Decodable {
        struct Content: Decodable {
            let parts: [Part]?
        }

        struct Part: Decodable {
            let text: String?
            let thought: Bool?
        }

        let content: Content?
        let finishReason: String?
    }

    struct PromptFeedback: Decodable {
        let blockReason: String?
    }

    let candidates: [Candidate]?
    let promptFeedback: PromptFeedback?
}

struct GeminiErrorResponse: Decodable {
    struct Detail: Decodable {
        let code: Int?
        let message: String?
        let status: String?
    }

    let error: Detail
}
