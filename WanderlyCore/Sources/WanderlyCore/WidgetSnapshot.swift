import Foundation

/// App 写给小组件的精简数据。小组件不直接读数据库。
public struct WidgetSnapshot: Codable, Sendable, Equatable {
    public struct Item: Codable, Sendable, Equatable, Identifiable {
        public var id: UUID
        public var title: String
        public var hasDue: Bool
        public var due: Date
        public var hasTime: Bool
        public var urgency: Urgency
        public var isRough: Bool

        public init(id: UUID, title: String, hasDue: Bool, due: Date, hasTime: Bool, urgency: Urgency, isRough: Bool) {
            self.id = id
            self.title = title
            self.hasDue = hasDue
            self.due = due
            self.hasTime = hasTime
            self.urgency = urgency
            self.isRough = isRough
        }

        /// 列表里显示的时间或紧急程度。
        public func caption(now: Date, calendar: Calendar = .current) -> String {
            let when = hasDue ? DueText.describe(due: due, hasTime: hasTime, now: now, calendar: calendar) : urgency.label
            return isRough ? "\(when) · 待完善" : when
        }
    }

    public struct Focus: Equatable, Sendable {
        public var heading: String
        /// 逾期、今天到期或者标为紧急的数量。
        public var urgentCount: Int
        public var items: [Item]
    }

    public var items: [Item]
    public var roughCount: Int

    public init(items: [Item], roughCount: Int) {
        self.items = items
        self.roughCount = roughCount
    }

    /// 只保留进行中、需要提醒的条目：有截止的按时间在前，其余按紧急程度，最多 20 条。
    public init(entries: [EntrySnapshot]) {
        let live = entries
            .filter { $0.state.isActive && $0.urgency != .archive }
            .sorted {
                ($0.hasDue ? $0.due : .distantFuture, $0.urgency.rank, $0.title)
                    < ($1.hasDue ? $1.due : .distantFuture, $1.urgency.rank, $1.title)
            }
        items = live.prefix(20).map {
            Item(id: $0.id, title: $0.title, hasDue: $0.hasDue, due: $0.due, hasTime: $0.hasTime, urgency: $0.urgency, isRough: $0.state == .rough)
        }
        roughCount = live.filter { $0.state == .rough }.count
    }

    public static let empty = WidgetSnapshot(items: [], roughCount: 0)

    /// 某个时刻要展示的内容：优先逾期、今天到期和紧急的，没有就显示接下来的。
    public func focus(at now: Date, limit: Int, calendar: Calendar = .current) -> Focus {
        let urgent = items.filter { item in
            item.urgency == .urgent
                || (item.hasDue && EntryGroup.of(due: item.due, hasTime: item.hasTime, now: now, calendar: calendar) <= .today)
        }
        if !urgent.isEmpty {
            return Focus(heading: "今天", urgentCount: urgent.count, items: Array(urgent.prefix(limit)))
        }
        return Focus(heading: items.isEmpty ? "没有待办" : "接下来", urgentCount: 0, items: Array(items.prefix(limit)))
    }

    /// 时间线需要刷新的时刻：下一个午夜，以及之后一天内有具体时间的事到点时（到点后要标成逾期）。
    public func refreshDates(after now: Date, calendar: Calendar = .current) -> [Date] {
        let midnight = calendar.date(byAdding: .day, value: 1, to: calendar.startOfDay(for: now))!
        let end = calendar.date(byAdding: .day, value: 1, to: midnight)!
        let timed = items.filter { $0.hasDue && $0.hasTime && $0.due > now && $0.due < end }.map(\.due)
        return Set(timed + [midnight]).sorted()
    }
}
