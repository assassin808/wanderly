import Foundation

/// 记下一段话后，AI 在后台起标题、归类、识别截止时间，并按类别提出深浅不同的追问。
public enum Organizer {
    public struct Input: Sendable, Equatable {
        public var text: String
        public var urgency: Urgency
        /// 本地已经识别出的截止描述，例如「周五 15:00」。
        public var knownDue: String?
        public var today: String

        public init(text: String, urgency: Urgency, knownDue: String?, today: String) {
            self.text = text
            self.urgency = urgency
            self.knownDue = knownDue
            self.today = today
        }
    }

    public struct Result: Sendable, Equatable {
        public var title: String
        public var category: EntryCategory
        public var summary: String
        public var due: DetectedDue?
        public var questions: [String]
    }

    static let system = """
    用户随手记下了一段话，可能是待办、会议、想法或资料。你在后台帮 TA 整理：

    1. title：不超过 16 个字的标题。
    2. category：todo（要去做的事）、meeting（会议或约定）、idea（想法、灵感、研究方向）、reference（资料、链接、摘录）、other。
    3. summary：用一两句话概括要点，只用原文里有的信息；原文本来就很短就留空。
    4. due：只有原文明确写了时间才填，格式 YYYY-MM-DD 或 YYYY-MM-DD HH:mm；否则留空。
    5. questions：之后回头看会缺的关键信息。
       - todo 和 meeting：最多 2 个，只问做这件事必须知道的，比如具体下一步、和谁、在哪、做到什么程度算完成；已经清楚就不问。
       - idea：2 到 3 个更深入的问题，帮 TA 想清楚动机、对象、假设、反例或可以先验证的一小步。
       - reference：通常不需要问。
       每个问题一两句话就能回答。不要替用户下结论或写方案，不要鼓励或催促。

    用原文使用的语言。
    """

    static let schema: OutputSchema = .object([
        .init("title", .string(description: "不超过 16 个字的标题")),
        .init("category", .choice(EntryCategory.allCases.map(\.rawValue), description: "类别")),
        .init("summary", .string(description: "一两句话概括要点；原文很短就留空")),
        .init("due", .string(description: "原文明确写出的截止时间，格式 YYYY-MM-DD 或 YYYY-MM-DD HH:mm；没有就留空")),
        .init("questions", .list(.string(description: "一个追问"), description: "追问，可以为空")),
    ])

    public static func request(_ input: Input) -> AIRequest {
        let prompt = """
        今天：\(input.today)
        紧急程度：\(input.urgency.label)
        已识别的截止：\(input.knownDue ?? "无")
        原文：
        \(input.text)
        """
        return AIRequest(system: system, turns: [ChatTurn(.user, prompt)], schema: schema, depth: .quick)
    }

    public static func parse(_ text: String, calendar: Calendar = .current) throws -> Result {
        struct Raw: Decodable {
            let title: String
            let category: String
            let summary: String
            let due: String
            let questions: [String]
        }
        let raw = try AIClient.decode(Raw.self, from: text)
        let category = EntryCategory(rawValue: raw.category.trimmed.lowercased()) ?? .other
        let limit: Int = switch category {
        case .idea: 3
        case .reference: 1
        default: 2
        }
        let questions = raw.questions.map(\.trimmed).filter { !$0.isEmpty }.prefix(limit)
        return Result(
            title: String(raw.title.trimmed.prefix(30)),
            category: category,
            summary: raw.summary.trimmed,
            due: parseDue(raw.due, calendar: calendar),
            questions: Array(questions))
    }

    static func parseDue(_ value: String, calendar: Calendar) -> DetectedDue? {
        guard let groups = DueParser.firstMatch(#"^\s*(\d{4})-(\d{1,2})-(\d{1,2})(?:[ T](\d{1,2}):(\d{2}))?\s*$"#, in: value),
              let year = Int(groups[1] ?? ""), let month = Int(groups[2] ?? ""), let day = Int(groups[3] ?? "") else {
            return nil
        }
        let hour = groups[4].flatMap { Int($0) }
        let minute = groups[5].flatMap { Int($0) } ?? 0
        if let hour, !(0...23).contains(hour) { return nil }
        guard (0...59).contains(minute),
              let date = calendar.date(from: DateComponents(year: year, month: month, day: day, hour: hour ?? 0, minute: minute)),
              calendar.component(.month, from: date) == month, calendar.component(.day, from: date) == day else {
            return nil
        }
        return DetectedDue(date: date, hasTime: hour != nil)
    }

    public static func run(_ input: Input, provider: AIProvider, apiKey: String, session: URLSession = .shared) async throws -> Result {
        let text = try await AIClient.complete(request(input), provider: provider, apiKey: apiKey, session: session)
        return try parse(text)
    }
}
