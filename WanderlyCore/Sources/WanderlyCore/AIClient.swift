import Foundation

/// AI 用哪家服务。
public enum AIProvider: String, CaseIterable, Sendable, Identifiable {
    case gemini
    case claude

    public var id: String { rawValue }

    public var displayName: String {
        switch self {
        case .gemini: "Gemini"
        case .claude: "Claude"
        }
    }
}

public enum AIError: LocalizedError, Equatable {
    case missingKey
    case invalidKey
    case rateLimited
    case overloaded
    case refused
    case api(status: Int, message: String)
    case badResponse

    public var errorDescription: String? {
        switch self {
        case .missingKey: "还没有 API Key，去设置里填一个。"
        case .invalidKey: "API Key 无效，去设置里检查一下。"
        case .rateLimited: "请求太频繁或额度用完了，稍后会自动重试。"
        case .overloaded: "AI 服务暂时繁忙，稍后会自动重试。"
        case .refused: "这条内容 AI 没法处理。"
        case let .api(status, message): "AI 请求失败（\(status)）\(message.isEmpty ? "" : "：\(message)")"
        case .badResponse: "AI 返回的内容没法解析。"
        }
    }

    /// 繁忙或限流：等一会儿再试通常就好。
    public var isTransient: Bool {
        self == .overloaded || self == .rateLimited
    }

    /// 繁忙、限流或模型不存在时换下一个模型；Key 无效等错误直接返回。
    var triesNextModel: Bool {
        switch self {
        case .overloaded, .rateLimited: true
        case let .api(status, _): status == 404
        default: false
        }
    }
}

/// 快速：待办、会议这类只需要简短回应的；深入：想法类，允许多想一会儿。
public enum AIDepth: Sendable {
    case quick
    case deep
}

public struct ChatTurn: Sendable, Equatable {
    public enum Role: String, Sendable {
        case user
        case assistant
    }

    public var role: Role
    public var text: String

    public init(_ role: Role, _ text: String) {
        self.role = role
        self.text = text
    }
}

/// 结构化输出的格式。两家 API 的写法不同，各自转换。
public indirect enum OutputSchema: Sendable {
    public struct Field: Sendable {
        public let name: String
        public let schema: OutputSchema

        public init(_ name: String, _ schema: OutputSchema) {
            self.name = name
            self.schema = schema
        }
    }

    case string(description: String)
    case choice([String], description: String)
    case list(OutputSchema, description: String)
    /// 所有字段都必填。
    case object([Field])

    func geminiJSON() -> [String: Any] {
        switch self {
        case let .string(description):
            return ["type": "STRING", "description": description]
        case let .choice(values, description):
            return ["type": "STRING", "enum": values, "description": description]
        case let .list(item, description):
            return ["type": "ARRAY", "items": item.geminiJSON(), "description": description]
        case let .object(fields):
            var properties: [String: Any] = [:]
            for field in fields { properties[field.name] = field.schema.geminiJSON() }
            return ["type": "OBJECT", "properties": properties, "required": fields.map(\.name), "propertyOrdering": fields.map(\.name)]
        }
    }

    func claudeJSON() -> [String: Any] {
        switch self {
        case let .string(description):
            return ["type": "string", "description": description]
        case let .choice(values, description):
            return ["type": "string", "enum": values, "description": description]
        case let .list(item, description):
            return ["type": "array", "items": item.claudeJSON(), "description": description]
        case let .object(fields):
            var properties: [String: Any] = [:]
            for field in fields { properties[field.name] = field.schema.claudeJSON() }
            return ["type": "object", "properties": properties, "required": fields.map(\.name), "additionalProperties": false]
        }
    }
}

public struct AIRequest: Sendable {
    public var system: String
    public var turns: [ChatTurn]
    /// 为 nil 时返回普通文本。
    public var schema: OutputSchema?
    public var depth: AIDepth

    public init(system: String, turns: [ChatTurn], schema: OutputSchema? = nil, depth: AIDepth = .quick) {
        self.system = system
        self.turns = turns
        self.schema = schema
        self.depth = depth
    }

    /// 两家 API 都要求第一条是用户消息、角色交替：合并连续同角色的消息，必要时在开头补一条。
    var normalizedTurns: [ChatTurn] {
        var merged: [ChatTurn] = []
        for turn in turns where !turn.text.trimmed.isEmpty {
            if let last = merged.last, last.role == turn.role {
                merged[merged.count - 1].text = last.text + "\n\n" + turn.text
            } else {
                merged.append(turn)
            }
        }
        if merged.first?.role != .user {
            merged.insert(ChatTurn(.user, "你好"), at: 0)
        }
        return merged
    }
}

public enum AIClient {
    public static func complete(_ request: AIRequest, provider: AIProvider, apiKey: String, session: URLSession = .shared) async throws -> String {
        guard !apiKey.trimmed.isEmpty else { throw AIError.missingKey }
        switch provider {
        case .gemini:
            return try await GeminiClient.complete(request, apiKey: apiKey, session: session)
        case .claude:
            return try await ClaudeClient.complete(request, apiKey: apiKey, session: session)
        }
    }

    /// 结构化输出偶尔会被包在代码块里，解析前去掉。
    static func stripFences(_ text: String) -> String {
        var value = text.trimmed
        if value.hasPrefix("```") {
            value = value.drop { $0 != "\n" }.dropFirst().description
            if value.hasSuffix("```") { value = String(value.dropLast(3)) }
        }
        return value.trimmed
    }

    static func decode<T: Decodable>(_ type: T.Type, from text: String) throws -> T {
        guard let value = try? JSONDecoder().decode(type, from: Data(stripFences(text).utf8)) else {
            throw AIError.badResponse
        }
        return value
    }
}
