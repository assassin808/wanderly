import Foundation
import Testing
@testable import WanderlyCore

struct ClaudeRefinerTests {
    let input = RefinementInput(text: "和导师聊 eval", details: "", nextStep: "", due: "周五", today: "2026年9月14日 星期一")

    @Test func requestShape() throws {
        let request = try ClaudeRefiner.makeRequest(apiKey: "sk-test", input: input)
        #expect(request.url?.absoluteString == "https://api.anthropic.com/v1/messages")
        #expect(request.value(forHTTPHeaderField: "x-api-key") == "sk-test")
        #expect(request.value(forHTTPHeaderField: "anthropic-version") == "2023-06-01")
        #expect(request.value(forHTTPHeaderField: "anthropic-beta") == "server-side-fallback-2026-07-01")

        let body = try #require(JSONSerialization.jsonObject(with: request.httpBody ?? Data()) as? [String: Any])
        #expect(body["model"] as? String == "claude-opus-5")
        #expect(body["fallbacks"] as? String == "default")
        #expect(body["max_tokens"] as? Int == 16000)
        let outputConfig = try #require(body["output_config"] as? [String: Any])
        let format = try #require(outputConfig["format"] as? [String: Any])
        #expect(format["type"] as? String == "json_schema")
        let schema = try #require(format["schema"] as? [String: Any])
        #expect(schema["additionalProperties"] as? Bool == false)
        #expect(schema["required"] as? [String] == ["questions"])

        let messages = try #require(body["messages"] as? [[String: Any]])
        let content = try #require(messages.first?["content"] as? String)
        #expect(content.contains("记下的：和导师聊 eval"))
        #expect(content.contains("细节：（还没写）"))
    }

    @Test func parsesQuestionsAfterThinkingBlock() throws {
        let data = Data(#"""
        {"stop_reason":"end_turn","content":[
          {"type":"thinking","thinking":""},
          {"type":"text","text":"{\"questions\":[\"想聊出什么结论？\",\" \",\"要带哪些结果？\",\"约在哪？\",\"多了一个\"]}"}
        ]}
        """#.utf8)
        #expect(try ClaudeRefiner.parse(data: data, status: 200) == ["想聊出什么结论？", "要带哪些结果？", "约在哪？"])
    }

    @Test func mapsFailures() {
        let refusal = Data(#"{"stop_reason":"refusal","content":[]}"#.utf8)
        #expect(throws: RefinerError.refused) { try ClaudeRefiner.parse(data: refusal, status: 200) }

        let error = Data(#"{"type":"error","error":{"type":"authentication_error","message":"invalid x-api-key"}}"#.utf8)
        #expect(throws: RefinerError.invalidKey) { try ClaudeRefiner.parse(data: error, status: 401) }
        #expect(throws: RefinerError.overloaded) { try ClaudeRefiner.parse(data: error, status: 529) }
        #expect(throws: RefinerError.api(status: 400, message: "invalid x-api-key")) { try ClaudeRefiner.parse(data: error, status: 400) }

        let garbage = Data(#"{"stop_reason":"end_turn","content":[{"type":"text","text":"not json"}]}"#.utf8)
        #expect(throws: RefinerError.badResponse) { try ClaudeRefiner.parse(data: garbage, status: 200) }
    }
}
