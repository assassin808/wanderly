import Foundation
import Testing
@testable import WanderlyCore

func jsonBody(_ request: URLRequest) throws -> [String: Any] {
    guard let object = try JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any] else {
        throw CocoaError(.coderReadCorrupt)
    }
    return object
}

struct AIClientTests {
    let request = AIRequest(
        system: "系统说明",
        turns: [ChatTurn(.assistant, "AI 先问的问题"), ChatTurn(.user, "回答一"), ChatTurn(.user, "回答二")],
        schema: .object([
            .init("title", .string(description: "标题")),
            .init("tags", .list(.choice(["a", "b"], description: "标签"), description: "标签列表")),
        ]),
        depth: .quick)

    @Test func normalizesTurnsForBothAPIs() {
        let turns = request.normalizedTurns
        #expect(turns.map(\.role) == [.user, .assistant, .user])
        #expect(turns[2].text == "回答一\n\n回答二")
    }

    @Test func geminiRequestShape() throws {
        let urlRequest = try GeminiClient.makeRequest(request, apiKey: "k", model: "gemini-flash-latest")
        #expect(urlRequest.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent")
        #expect(urlRequest.value(forHTTPHeaderField: "x-goog-api-key") == "k")

        let body = try jsonBody(urlRequest)
        let contents = try #require(body["contents"] as? [[String: Any]])
        #expect(contents.map { $0["role"] as? String } == ["user", "model", "user"])
        let config = try #require(body["generationConfig"] as? [String: Any])
        #expect(config["responseMimeType"] as? String == "application/json")
        #expect((config["thinkingConfig"] as? [String: Any])?["thinkingLevel"] as? String == "low")
        let schema = try #require(config["responseSchema"] as? [String: Any])
        #expect(schema["type"] as? String == "OBJECT")
        #expect(schema["required"] as? [String] == ["title", "tags"])
        let tags = try #require((schema["properties"] as? [String: Any])?["tags"] as? [String: Any])
        #expect((tags["items"] as? [String: Any])?["enum"] as? [String] == ["a", "b"])
    }

    @Test func geminiDeepChatUsesProWithDefaultThinking() throws {
        let chat = AIRequest(system: "s", turns: [ChatTurn(.user, "hi")], depth: .deep)
        #expect(GeminiClient.models(for: .deep) == ["gemini-pro-latest", "gemini-flash-latest", "gemini-flash-lite-latest"])
        #expect(AIError.overloaded.isTransient && AIError.rateLimited.isTransient && !AIError.invalidKey.isTransient)
        let body = try jsonBody(GeminiClient.makeRequest(chat, apiKey: "k", model: "gemini-pro-latest"))
        #expect(body["generationConfig"] == nil)
    }

    @Test func claudeRequestShape() throws {
        let urlRequest = try ClaudeClient.makeRequest(request, apiKey: "k")
        #expect(urlRequest.value(forHTTPHeaderField: "x-api-key") == "k")
        #expect(urlRequest.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")
        let body = try jsonBody(urlRequest)
        #expect(body["model"] as? String == "claude-opus-5")
        #expect(body["fallbacks"] as? String == "default")
        let messages = try #require(body["messages"] as? [[String: Any]])
        #expect(messages.map { $0["role"] as? String } == ["user", "assistant", "user"])
        let output = try #require(body["output_config"] as? [String: Any])
        #expect(output["effort"] as? String == "low")
        let schema = try #require((output["format"] as? [String: Any])?["schema"] as? [String: Any])
        #expect(schema["additionalProperties"] as? Bool == false)
    }

    @Test func parsesGeminiTextSkippingThoughts() throws {
        let data = Data(#"{"candidates":[{"content":{"parts":[{"text":"先想想","thought":true},{"text":"你好"}]},"finishReason":"STOP"}]}"#.utf8)
        #expect(try GeminiClient.parseText(data: data, status: 200) == "你好")
    }

    @Test func mapsGeminiFailures() {
        #expect(throws: AIError.refused) {
            try GeminiClient.parseText(data: Data(#"{"promptFeedback":{"blockReason":"SAFETY"}}"#.utf8), status: 200)
        }
        #expect(throws: AIError.invalidKey) {
            try GeminiClient.parseText(data: Data(#"{"error":{"code":400,"message":"API key not valid."}}"#.utf8), status: 400)
        }
        #expect(throws: AIError.rateLimited) { try GeminiClient.parseText(data: Data("{}".utf8), status: 429) }
        #expect(throws: AIError.overloaded) { try GeminiClient.parseText(data: Data("{}".utf8), status: 503) }
    }

    @Test func parsesClaudeTextAndFailures() throws {
        let data = Data(#"{"stop_reason":"end_turn","content":[{"type":"thinking"},{"type":"text","text":"好的"}]}"#.utf8)
        #expect(try ClaudeClient.parseText(data: data, status: 200) == "好的")
        #expect(throws: AIError.refused) {
            try ClaudeClient.parseText(data: Data(#"{"stop_reason":"refusal","content":[]}"#.utf8), status: 200)
        }
        #expect(throws: AIError.invalidKey) {
            try ClaudeClient.parseText(data: Data(#"{"error":{"type":"authentication_error","message":"bad"}}"#.utf8), status: 401)
        }
    }

    @Test func geminiFallsBackToNextModelWhenBusy() async throws {
        let stub = StubResponses([
            (503, #"{"error":{"code":503,"message":"high demand"}}"#),
            (200, #"{"candidates":[{"content":{"parts":[{"text":"第二个模型的回答"}]},"finishReason":"STOP"}]}"#),
        ])
        let text = try await AIClient.complete(request, provider: .gemini, apiKey: "k", session: stub.session)
        #expect(text == "第二个模型的回答")
        #expect(stub.requestedPaths == ["gemini-flash-latest:generateContent", "gemini-flash-lite-latest:generateContent"])
    }

    @Test func invalidKeyDoesNotTryOtherModels() async {
        let stub = StubResponses([(400, #"{"error":{"code":400,"message":"API key not valid."}}"#)])
        await #expect(throws: AIError.invalidKey) {
            try await AIClient.complete(request, provider: .gemini, apiKey: "k", session: stub.session)
        }
        #expect(stub.requestedPaths.count == 1)
    }

    @Test func missingKeyFailsWithoutRequest() async {
        await #expect(throws: AIError.missingKey) {
            try await AIClient.complete(request, provider: .gemini, apiKey: "  ")
        }
    }

    @Test func stripsCodeFences() {
        #expect(AIClient.stripFences("```json\n{\"a\":1}\n```") == #"{"a":1}"#)
        #expect(AIClient.stripFences(#" {"a":1} "#) == #"{"a":1}"#)
    }

    /// 设置了 GEMINI_API_KEY 才会真的调用接口。
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GEMINI_API_KEY"] != nil))
    func liveOrganize() async throws {
        let key = try #require(ProcessInfo.processInfo.environment["GEMINI_API_KEY"])
        let input = Organizer.Input(text: "周五下午和导师聊聊让 agent 自己写 eval 再自己打分的想法", urgency: .soon, knownDue: nil, today: "2026年9月14日 星期一")
        let result = try await Organizer.run(input, provider: .gemini, apiKey: key)
        #expect(!result.title.isEmpty)
        print("Organized:", result)
    }
}
