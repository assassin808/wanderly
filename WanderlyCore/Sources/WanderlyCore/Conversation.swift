import Foundation

/// 每条记录都可以和 AI 来回聊。想法类聊得更深，其他的回复保持简短。
public enum Conversation {
    public struct Context: Sendable, Equatable {
        public var title: String
        public var category: EntryCategory
        public var text: String
        public var summary: String

        public init(title: String, category: EntryCategory, text: String, summary: String) {
            self.title = title
            self.category = category
            self.text = text
            self.summary = summary
        }
    }

    public static func request(context: Context, history: [ChatTurn]) -> AIRequest {
        AIRequest(
            system: system(for: context),
            turns: [ChatTurn(.user, "这是我记下的内容：\n\(context.text)")] + history,
            schema: nil,
            depth: context.category == .idea ? .deep : .quick)
    }

    static func system(for context: Context) -> String {
        let style = context.category == .idea
            ? "这是一个还在酝酿的想法。像一个好奇、敏锐的同伴一样聊：先回应 TA 刚说的，再帮 TA 看清动机、对象、假设、反例，或者可以先验证的一小步。可以给出相关的视角和例子，但不要替 TA 做决定。通常以一个问题结尾。回复不超过 250 字。"
            : "这是一件要处理的事。回复简短，三句话以内，帮 TA 把事情说清楚、能执行。需要的话再问一个问题。"
        return """
        你在 Wanderly 里陪用户完善 TA 随手记下的一条记录。
        标题：\(context.title)
        类别：\(context.category.label)
        AI 整理：\(context.summary.isEmpty ? "无" : context.summary)

        \(style)
        不要鼓励或催促，不写客套话。用用户使用的语言回复。
        """
    }

    public static func reply(context: Context, history: [ChatTurn], provider: AIProvider, apiKey: String, session: URLSession = .shared) async throws -> String {
        try await AIClient.complete(request(context: context, history: history), provider: provider, apiKey: apiKey, session: session).trimmed
    }
}

/// Beta：隔几天对还在酝酿的想法抛出一个新问题。
public enum Watering {
    static let system = "用户几天前记下了一个想法，还在酝酿。根据已有内容和对话，提出一个之前没问过、能帮 TA 往前想一步的问题。只输出这个问题本身，不超过 40 个字。"

    public static func request(context: Conversation.Context, history: [ChatTurn]) -> AIRequest {
        AIRequest(
            system: system + "\n想法标题：\(context.title)",
            turns: [ChatTurn(.user, "这是我记下的想法：\n\(context.text)")] + history + [ChatTurn(.user, "过了几天，再问我一个新问题吧。")],
            schema: nil,
            depth: .deep)
    }

    /// 取第一行非空文字，去掉引号。
    public static func parse(_ text: String) -> String? {
        let quotes = CharacterSet(charactersIn: "\"'“”‘’「」『』")
        return text
            .split(whereSeparator: \.isNewline)
            .map { $0.trimmingCharacters(in: .whitespaces).trimmingCharacters(in: quotes) }
            .first { !$0.isEmpty }
    }

    public static func question(context: Conversation.Context, history: [ChatTurn], provider: AIProvider, apiKey: String, session: URLSession = .shared) async throws -> String {
        let text = try await AIClient.complete(request(context: context, history: history), provider: provider, apiKey: apiKey, session: session)
        guard let question = parse(text) else { throw AIError.badResponse }
        return question
    }
}
