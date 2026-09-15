import Foundation

/// Gemini generateContent 接口。免费额度下单个模型经常繁忙或限流，按顺序换着试。
public enum GeminiClient {
    public static func models(for depth: AIDepth) -> [String] {
        switch depth {
        case .quick: ["gemini-flash-latest", "gemini-flash-lite-latest"]
        case .deep: ["gemini-pro-latest", "gemini-flash-latest", "gemini-flash-lite-latest"]
        }
    }

    public static func makeRequest(_ request: AIRequest, apiKey: String, model: String) throws -> URLRequest {
        var urlRequest = URLRequest(
            url: URL(string: "https://generativelanguage.googleapis.com/v1beta/models/\(model):generateContent")!,
            timeoutInterval: 90)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-goog-api-key")

        var generationConfig: [String: Any] = [:]
        if let schema = request.schema {
            generationConfig["responseMimeType"] = "application/json"
            generationConfig["responseSchema"] = schema.geminiJSON()
        }
        if request.depth == .quick {
            generationConfig["thinkingConfig"] = ["thinkingLevel": "low"]
        }
        var body: [String: Any] = [
            "systemInstruction": ["parts": [["text": request.system]]],
            "contents": request.normalizedTurns.map { turn in
                ["role": turn.role == .user ? "user" : "model", "parts": [["text": turn.text]]]
            },
        ]
        if !generationConfig.isEmpty {
            body["generationConfig"] = generationConfig
        }
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    public static func parseText(data: Data, status: Int) throws -> String {
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message ?? ""
            switch status {
            case 400 where message.localizedCaseInsensitiveContains("API key"):
                throw AIError.invalidKey
            case 401, 403:
                throw AIError.invalidKey
            case 429:
                throw AIError.rateLimited
            case 500...599:
                throw AIError.overloaded
            default:
                throw AIError.api(status: status, message: message)
            }
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw AIError.badResponse
        }
        if response.promptFeedback?.blockReason != nil { throw AIError.refused }
        guard let candidate = response.candidates?.first else { throw AIError.badResponse }
        if let reason = candidate.finishReason, ["SAFETY", "PROHIBITED_CONTENT", "BLOCKLIST", "SPII"].contains(reason) {
            throw AIError.refused
        }
        let text = (candidate.content?.parts ?? [])
            .filter { $0.thought != true }
            .compactMap(\.text)
            .joined()
        guard !text.trimmed.isEmpty else { throw AIError.badResponse }
        return text
    }

    public static func complete(_ request: AIRequest, apiKey: String, session: URLSession = .shared) async throws -> String {
        var lastError = AIError.overloaded
        for model in models(for: request.depth) {
            let (data, response) = try await session.data(for: makeRequest(request, apiKey: apiKey, model: model))
            do {
                return try parseText(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
            } catch let error as AIError where error.triesNextModel {
                lastError = error
            }
        }
        throw lastError
    }

    struct Response: Decodable {
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

    struct ErrorResponse: Decodable {
        struct Detail: Decodable {
            let message: String?
        }

        let error: Detail
    }
}
