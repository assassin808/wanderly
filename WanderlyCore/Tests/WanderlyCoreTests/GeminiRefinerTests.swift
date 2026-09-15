import Foundation
import Testing
@testable import WanderlyCore

struct GeminiRefinerTests {
    let input = RefinementInput(text: "和导师聊 eval", details: "", nextStep: "", due: "周五", today: "2026年9月14日 星期一")

    @Test func requestShape() throws {
        let request = try GeminiRefiner.makeRequest(apiKey: "test-key", input: input)
        #expect(request.url?.absoluteString == "https://generativelanguage.googleapis.com/v1beta/models/gemini-flash-latest:generateContent")
        #expect(request.value(forHTTPHeaderField: "x-goog-api-key") == "test-key")

        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        let config = try #require(body["generationConfig"] as? [String: Any])
        #expect(config["responseMimeType"] as? String == "application/json")
        let schema = try #require(config["responseSchema"] as? [String: Any])
        #expect(schema["type"] as? String == "OBJECT")
        #expect(schema["required"] as? [String] == ["questions"])

        let system = try #require(body["systemInstruction"] as? [String: Any])
        #expect(system["role"] == nil)
        let systemParts = try #require(system["parts"] as? [[String: Any]])
        #expect((systemParts.first?["text"] as? String)?.contains("只提问") == true)

        let contents = try #require(body["contents"] as? [[String: Any]])
        #expect(contents.first?["role"] as? String == "user")
        let parts = try #require(contents.first?["parts"] as? [[String: Any]])
        #expect((parts.first?["text"] as? String)?.contains("记下的：和导师聊 eval") == true)
    }

    @Test func parsesTextSkippingThoughts() throws {
        let data = Data(#"""
        {"candidates":[{"content":{"role":"model","parts":[
          {"text":"先想想","thought":true},
          {"text":"{\"questions\":[\"想聊出什么结论？\",\"要带哪些结果？\"]}"}
        ]},"finishReason":"STOP"}]}
        """#.utf8)
        #expect(try GeminiRefiner.parse(data: data, status: 200) == ["想聊出什么结论？", "要带哪些结果？"])
    }

    @Test func mapsFailures() {
        let blocked = Data(#"{"promptFeedback":{"blockReason":"SAFETY"}}"#.utf8)
        #expect(throws: RefinerError.refused) { try GeminiRefiner.parse(data: blocked, status: 200) }

        let safety = Data(#"{"candidates":[{"finishReason":"SAFETY"}]}"#.utf8)
        #expect(throws: RefinerError.refused) { try GeminiRefiner.parse(data: safety, status: 200) }

        let badKey = Data(#"{"error":{"code":400,"message":"API key not valid. Please pass a valid API key.","status":"INVALID_ARGUMENT"}}"#.utf8)
        #expect(throws: RefinerError.invalidKey) { try GeminiRefiner.parse(data: badKey, status: 400) }

        let quota = Data(#"{"error":{"code":429,"message":"Resource has been exhausted","status":"RESOURCE_EXHAUSTED"}}"#.utf8)
        #expect(throws: RefinerError.rateLimited) { try GeminiRefiner.parse(data: quota, status: 429) }
    }

    @Test func fallsBackToNextModelWhenBusy() async throws {
        let stub = StubResponses([
            (503, #"{"error":{"code":503,"message":"high demand","status":"UNAVAILABLE"}}"#),
            (200, #"{"candidates":[{"content":{"parts":[{"text":"{\"questions\":[\"问题一\"]}"}]},"finishReason":"STOP"}]}"#),
        ])
        let questions = try await GeminiRefiner.askQuestions(apiKey: "k", input: input, session: stub.session)
        #expect(questions == ["问题一"])
        #expect(stub.requestedPaths == ["gemini-flash-latest:generateContent", "gemini-flash-lite-latest:generateContent"])
    }

    @Test func invalidKeyDoesNotTryOtherModels() async {
        let stub = StubResponses([
            (400, #"{"error":{"code":400,"message":"API key not valid.","status":"INVALID_ARGUMENT"}}"#),
        ])
        await #expect(throws: RefinerError.invalidKey) {
            try await GeminiRefiner.askQuestions(apiKey: "k", input: input, session: stub.session)
        }
        #expect(stub.requestedPaths.count == 1)
    }

    /// 设置了 GEMINI_API_KEY 才会真的调用接口。
    @Test(.enabled(if: ProcessInfo.processInfo.environment["GEMINI_API_KEY"] != nil))
    func liveQuestions() async throws {
        let key = try #require(ProcessInfo.processInfo.environment["GEMINI_API_KEY"])
        let questions = try await GeminiRefiner.askQuestions(apiKey: key, input: input)
        #expect((1...3).contains(questions.count))
        print("Gemini questions:", questions)
    }
}
