import Foundation

/// Claude Messages API。Swift 没有官方 SDK，这里直接发 HTTP 请求。
public enum ClaudeClient {
    public static let model = "claude-opus-5"

    public static func makeRequest(_ request: AIRequest, apiKey: String) throws -> URLRequest {
        var urlRequest = URLRequest(url: URL(string: "https://api.anthropic.com/v1/messages")!, timeoutInterval: 120)
        urlRequest.httpMethod = "POST"
        urlRequest.setValue("application/json", forHTTPHeaderField: "content-type")
        urlRequest.setValue(apiKey, forHTTPHeaderField: "x-api-key")
        urlRequest.setValue("2023-06-01", forHTTPHeaderField: "anthropic-version")
        // 被安全分类器拒绝时，由服务端自动换推荐的模型重试。
        urlRequest.setValue("server-side-fallback-2026-07-01", forHTTPHeaderField: "anthropic-beta")

        var outputConfig: [String: Any] = ["effort": request.depth == .deep ? "medium" : "low"]
        if let schema = request.schema {
            outputConfig["format"] = ["type": "json_schema", "schema": schema.claudeJSON()]
        }
        let body: [String: Any] = [
            "model": model,
            "max_tokens": 16000,
            "fallbacks": "default",
            "system": request.system,
            "output_config": outputConfig,
            "messages": request.normalizedTurns.map { ["role": $0.role.rawValue, "content": $0.text] },
        ]
        urlRequest.httpBody = try JSONSerialization.data(withJSONObject: body)
        return urlRequest
    }

    public static func parseText(data: Data, status: Int) throws -> String {
        guard (200..<300).contains(status) else {
            let message = (try? JSONDecoder().decode(ErrorResponse.self, from: data))?.error.message ?? ""
            switch status {
            case 401: throw AIError.invalidKey
            case 429: throw AIError.rateLimited
            case 500...599: throw AIError.overloaded
            default: throw AIError.api(status: status, message: message)
            }
        }
        guard let response = try? JSONDecoder().decode(Response.self, from: data) else {
            throw AIError.badResponse
        }
        if response.stopReason == "refusal" { throw AIError.refused }
        let text = response.content.filter { $0.type == "text" }.compactMap(\.text).joined()
        guard !text.trimmed.isEmpty else { throw AIError.badResponse }
        return text
    }

    public static func complete(_ request: AIRequest, apiKey: String, session: URLSession = .shared) async throws -> String {
        let (data, response) = try await session.data(for: makeRequest(request, apiKey: apiKey))
        return try parseText(data: data, status: (response as? HTTPURLResponse)?.statusCode ?? 0)
    }

    struct Response: Decodable {
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

    struct ErrorResponse: Decodable {
        struct Detail: Decodable {
            let message: String
        }

        let error: Detail
    }
}
