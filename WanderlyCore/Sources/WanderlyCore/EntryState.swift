import Foundation

/// 一条记录的生命周期：速记 → 待办 → 完成 / 放弃。
public enum EntryState: String, Codable, Sendable, CaseIterable {
    /// 匆忙记下，还没完善。
    case rough
    /// 已经完善，等着去做。
    case open
    case done
    case dropped

    public var isActive: Bool { self == .rough || self == .open }

    public var label: String {
        switch self {
        case .rough: "待完善"
        case .open: "待办"
        case .done: "已完成"
        case .dropped: "已放弃"
        }
    }
}

/// 计算提醒所需的最小信息。和 SwiftData 模型解耦，方便测试。
public struct EntrySnapshot: Sendable, Equatable, Identifiable {
    public var id: UUID
    public var title: String
    public var due: Date
    public var hasTime: Bool
    public var state: EntryState

    public init(id: UUID = UUID(), title: String, due: Date, hasTime: Bool = false, state: EntryState = .rough) {
        self.id = id
        self.title = title
        self.due = due
        self.hasTime = hasTime
        self.state = state
    }
}
