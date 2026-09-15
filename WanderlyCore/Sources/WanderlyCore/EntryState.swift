import Foundation

/// 一条记录的生命周期：速记 → 待办 → 完成 / 放弃。
public enum EntryState: String, Codable, Sendable, CaseIterable {
    /// 刚记下，还没完善（AI 的问题还没回答）。
    case rough
    /// 已经完善，等着去做。
    case open
    case done
    case dropped

    public var isActive: Bool { self == .rough || self == .open }

    public var label: String {
        switch self {
        case .rough: "待完善"
        case .open: "进行中"
        case .done: "已完成"
        case .dropped: "已放弃"
        }
    }
}

/// 紧急程度决定多久提醒一次。有截止日期的事另外到点提醒。
public enum Urgency: String, Codable, Sendable, CaseIterable, Identifiable {
    case urgent
    case soon
    case later
    /// 只让 AI 整理，从不提醒。
    case archive

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .urgent: "紧急"
        case .soon: "这几天"
        case .later: "不急"
        case .archive: "只记录"
        }
    }

    /// 定期提醒的间隔天数；只记录的不提醒。
    public var intervalDays: Int? {
        switch self {
        case .urgent: 1
        case .soon: 2
        case .later: 7
        case .archive: nil
        }
    }

    var rank: Int {
        switch self {
        case .urgent: 0
        case .soon: 1
        case .later: 2
        case .archive: 3
        }
    }
}

/// AI 整理出来的类别。
public enum EntryCategory: String, Codable, Sendable, CaseIterable, Identifiable {
    case todo
    case meeting
    case idea
    case reference
    case other

    public var id: String { rawValue }

    public var label: String {
        switch self {
        case .todo: "待办"
        case .meeting: "会议"
        case .idea: "想法"
        case .reference: "资料"
        case .other: "其他"
        }
    }

    public var systemImage: String {
        switch self {
        case .todo: "checklist"
        case .meeting: "person.2"
        case .idea: "lightbulb"
        case .reference: "bookmark"
        case .other: "square.text.square"
        }
    }
}

/// 计算提醒和列表分组所需的信息。和 SwiftData 模型解耦，方便测试。
public struct EntrySnapshot: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var state: EntryState
    public var urgency: Urgency
    public var hasDue: Bool
    public var due: Date
    public var hasTime: Bool
    public var createdAt: Date
    /// 用户最近一次处理这条记录（回复 AI、编辑、标记完善）的时间。
    public var lastActivityAt: Date?
    public var refinedAt: Date?
    /// 「稍后提醒」「明天再问」约定的时间。
    public var snoozedUntil: Date?
    /// 还没回答的 AI 问题，用在提醒正文里。
    public var prompt: String?
    /// AI 最近一次主动抛出新问题（浇水）的时间。
    public var promptAt: Date?

    public init(
        id: UUID = UUID(),
        title: String,
        due: Date = Date(),
        hasTime: Bool = false,
        state: EntryState = .rough,
        urgency: Urgency = .soon,
        hasDue: Bool = true,
        createdAt: Date = .distantPast,
        lastActivityAt: Date? = nil,
        refinedAt: Date? = nil,
        snoozedUntil: Date? = nil,
        prompt: String? = nil,
        promptAt: Date? = nil
    ) {
        self.id = id
        self.title = title
        self.due = due
        self.hasTime = hasTime
        self.state = state
        self.urgency = urgency
        self.hasDue = hasDue
        self.createdAt = createdAt
        self.lastActivityAt = lastActivityAt
        self.refinedAt = refinedAt
        self.snoozedUntil = snoozedUntil
        self.prompt = prompt
        self.promptAt = promptAt
    }
}

/// 列表里的分区：先是逾期和今天到期的，然后按紧急程度。
public enum ListSection: Int, CaseIterable, Comparable, Sendable {
    case attention
    case urgent
    case soon
    case later
    case archive

    public var title: String {
        switch self {
        case .attention: "逾期和今天"
        case .urgent: "紧急"
        case .soon: "这几天"
        case .later: "不急"
        case .archive: "只记录"
        }
    }

    public static func of(_ entry: EntrySnapshot, now: Date, calendar: Calendar = .current) -> ListSection {
        if entry.hasDue, EntryGroup.of(due: entry.due, hasTime: entry.hasTime, now: now, calendar: calendar) <= .today {
            return .attention
        }
        switch entry.urgency {
        case .urgent: return .urgent
        case .soon: return .soon
        case .later: return .later
        case .archive: return .archive
        }
    }

    public static func < (lhs: ListSection, rhs: ListSection) -> Bool { lhs.rawValue < rhs.rawValue }
}

extension String {
    var trimmed: String { trimmingCharacters(in: .whitespacesAndNewlines) }
}
