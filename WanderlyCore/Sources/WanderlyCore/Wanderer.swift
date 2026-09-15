import Foundation

/// Beta 漫游：从几个想法里找出可能的联系。结果只是推测，由用户决定采纳还是删掉。
public enum Wanderer {
    public struct Idea: Sendable, Equatable {
        public var id: UUID
        public var title: String
        public var summary: String

        public init(id: UUID, title: String, summary: String) {
            self.id = id
            self.title = title
            self.summary = summary
        }
    }

    public struct Link: Sendable, Equatable {
        public var sourceIDs: [UUID]
        public var title: String
        public var insight: String
        public var question: String
    }

    static let system = "下面是用户记下的一些想法。挑出 2 到 3 个表面上关系不大、放在一起却可能碰出新东西的想法，说说它们之间可能的联系。这只是推测，语气不要太肯定。用想法使用的语言。"

    static let schema: OutputSchema = .object([
        .init("sources", .list(.string(description: "想法编号"), description: "用到的 2 到 3 个想法编号")),
        .init("title", .string(description: "不超过 16 个字的标题")),
        .init("insight", .string(description: "两三句话说明可能的联系")),
        .init("question", .string(description: "一个值得想一想的问题")),
    ])

    public static func request(ideas: [Idea]) -> AIRequest {
        let list = ideas.enumerated().map { index, idea in
            "\(index + 1). \(idea.title)\(idea.summary.isEmpty ? "" : "：\(idea.summary)")"
        }.joined(separator: "\n")
        return AIRequest(system: system, turns: [ChatTurn(.user, list)], schema: schema, depth: .deep)
    }

    public static func parse(_ text: String, ideas: [Idea]) throws -> Link {
        struct Raw: Decodable {
            let sources: [String]
            let title: String
            let insight: String
            let question: String
        }
        let raw = try AIClient.decode(Raw.self, from: text)
        var ids: [UUID] = []
        for source in raw.sources {
            guard let number = Int(source.filter(\.isNumber)), ideas.indices.contains(number - 1) else { continue }
            let id = ideas[number - 1].id
            if !ids.contains(id) { ids.append(id) }
        }
        guard ids.count >= 2, !raw.insight.trimmed.isEmpty else { throw AIError.badResponse }
        return Link(sourceIDs: Array(ids.prefix(3)), title: raw.title.trimmed, insight: raw.insight.trimmed, question: raw.question.trimmed)
    }

    public static func wander(ideas: [Idea], provider: AIProvider, apiKey: String, session: URLSession = .shared) async throws -> Link {
        let text = try await AIClient.complete(request(ideas: ideas), provider: provider, apiKey: apiKey, session: session)
        return try parse(text, ideas: ideas)
    }
}
