import Foundation
import Testing
@testable import WanderlyCore

struct OrganizerTests {
    @Test func requestCarriesContextAndSchema() {
        let request = Organizer.request(.init(text: "周五和导师聊 eval", urgency: .urgent, knownDue: "周五", today: "2026年9月14日"))
        #expect(request.depth == .quick)
        #expect(request.schema != nil)
        let prompt = request.turns.first?.text ?? ""
        #expect(prompt.contains("紧急程度：紧急"))
        #expect(prompt.contains("已识别的截止：周五"))
        #expect(prompt.hasSuffix("周五和导师聊 eval"))
    }

    @Test func parsesIdeaResult() throws {
        let json = #"{"title":"和导师聊 eval","category":"IDEA","summary":"想让 agent 自己写 eval","due":"2026-09-18 15:00","questions":["想验证什么？"," ","谁来打分？","第三个","第四个"]}"#
        let result = try Organizer.parse(json, calendar: cal)
        #expect(result.title == "和导师聊 eval")
        #expect(result.category == .idea)
        #expect(result.summary == "想让 agent 自己写 eval")
        #expect(result.due == DetectedDue(date: d(2026, 9, 18, 15), hasTime: true))
        #expect(result.questions == ["想验证什么？", "谁来打分？", "第三个"])
    }

    @Test func todosGetFewerQuestionsAndDatesAreValidated() throws {
        let todo = try Organizer.parse(#"{"title":"交报销","category":"todo","summary":"","due":"2026-02-30","questions":["一","二","三"]}"#, calendar: cal)
        #expect(todo.questions == ["一", "二"])
        #expect(todo.due == nil)

        let other = try Organizer.parse(#"{"title":"a","category":"unknown","summary":"","due":"2026-09-20","questions":[]}"#, calendar: cal)
        #expect(other.category == .other)
        #expect(other.due == DetectedDue(date: d(2026, 9, 20), hasTime: false))
    }

    @Test func rejectsGarbage() {
        #expect(throws: AIError.badResponse) { try Organizer.parse("不是 JSON", calendar: cal) }
    }
}

struct ConversationTests {
    let idea = Conversation.Context(title: "agent 写 eval", category: .idea, text: "让 agent 自己写 eval", summary: "")

    @Test func ideasGetDeeperConversations() {
        let request = Conversation.request(context: idea, history: [ChatTurn(.assistant, "想验证什么？"), ChatTurn(.user, "质量")])
        #expect(request.depth == .deep)
        #expect(request.schema == nil)
        #expect(request.normalizedTurns.map(\.role) == [.user, .assistant, .user])
        #expect(request.normalizedTurns.first?.text.contains("让 agent 自己写 eval") == true)
        #expect(request.system.contains("酝酿的想法"))
    }

    @Test func todosStayShort() {
        let todo = Conversation.Context(title: "交报销", category: .todo, text: "交报销", summary: "")
        let request = Conversation.request(context: todo, history: [])
        #expect(request.depth == .quick)
        #expect(request.system.contains("三句话以内"))
    }

    @Test func wateringKeepsOneQuestion() {
        #expect(Watering.parse("「如果只能做一个实验，你会先做什么？」\n补充说明") == "如果只能做一个实验，你会先做什么？")
        #expect(Watering.parse("  \n ") == nil)
        #expect(Watering.request(context: idea, history: []).normalizedTurns.count == 1)
    }
}

struct WandererTests {
    let ideas = [
        Wanderer.Idea(id: UUID(), title: "agent 写 eval", summary: ""),
        Wanderer.Idea(id: UUID(), title: "城市里的安静角落", summary: "收集不被标记的避难所"),
        Wanderer.Idea(id: UUID(), title: "睡前念头", summary: ""),
    ]

    @Test func listsIdeasWithNumbers() {
        let text = Wanderer.request(ideas: ideas).turns.first?.text ?? ""
        #expect(text == "1. agent 写 eval\n2. 城市里的安静角落：收集不被标记的避难所\n3. 睡前念头")
    }

    @Test func mapsSourcesBackToIdeas() throws {
        let link = try Wanderer.parse(#"{"sources":["3","1","3","9"],"title":"睡前的 eval","insight":"也许睡前的念头可以当评测题。","question":"会怎样？"}"#, ideas: ideas)
        #expect(link.sourceIDs == [ideas[2].id, ideas[0].id])
        #expect(link.title == "睡前的 eval")
    }

    @Test func needsAtLeastTwoIdeas() {
        #expect(throws: AIError.badResponse) {
            try Wanderer.parse(#"{"sources":["1"],"title":"t","insight":"i","question":"q"}"#, ideas: ideas)
        }
    }
}

struct MarkdownExportTests {
    @Test func exportsEntryWithConversation() {
        let markdown = MarkdownExport.entry(
            title: "agent 写 eval", category: .idea, urgency: .later, due: nil,
            text: "让 agent 自己写 eval", summary: "想法概括",
            messages: [.init(role: .assistant, text: "想验证什么？"), .init(role: .user, text: "质量")])
        #expect(markdown == """
        # agent 写 eval

        - 类别：想法
        - 紧急程度：不急

        ## 原文

        让 agent 自己写 eval

        ## AI 整理

        想法概括

        ## 对话

        **AI**：想验证什么？

        **我**：质量

        """)
    }

    @Test func skipsEmptySections() {
        let markdown = MarkdownExport.entry(title: "t", category: nil, urgency: .urgent, due: "明天", text: "x", summary: "", messages: [])
        #expect(markdown == "# t\n\n- 紧急程度：紧急\n- 截止：明天\n\n## 原文\n\nx\n")
    }
}
