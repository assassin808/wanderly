import Foundation

/// 速记时的截止日期快捷选项。
public enum DueShortcut: String, CaseIterable, Sendable, Identifiable {
    case today
    case tomorrow
    case weekend
    case nextWeekend

    public var id: String { rawValue }

    /// 目标日期的 0 点。
    public func date(from now: Date, calendar: Calendar = .current) -> Date {
        let today = calendar.startOfDay(for: now)
        let days: Int = switch self {
        case .today: 0
        case .tomorrow: 1
        case .weekend: Self.daysUntilSunday(from: today, calendar: calendar)
        case .nextWeekend: Self.daysUntilSunday(from: today, calendar: calendar) + 7
        }
        return calendar.date(byAdding: .day, value: days, to: today)!
    }

    public func label(from now: Date, calendar: Calendar = .current) -> String {
        switch self {
        case .today: "今天"
        case .tomorrow: "明天"
        case .weekend: "周末 " + DueText.monthDay(date(from: now, calendar: calendar), calendar: calendar)
        case .nextWeekend: "下周末 " + DueText.monthDay(date(from: now, calendar: calendar), calendar: calendar)
        }
    }

    /// 某个截止日期正好对应的快捷选项（用于高亮）。
    public static func matching(due: Date, hasTime: Bool, now: Date, calendar: Calendar = .current) -> DueShortcut? {
        guard !hasTime else { return nil }
        return allCases.first { calendar.isDate($0.date(from: now, calendar: calendar), inSameDayAs: due) }
    }

    static func daysUntilSunday(from day: Date, calendar: Calendar) -> Int {
        (8 - calendar.component(.weekday, from: day)) % 7
    }
}

public enum DueMath {
    /// 推迟。没有具体时间的事，从「原截止日和今天中较晚的一天」往后推；
    /// 有具体时间的事保持时刻不变，推到将来。
    public static func snoozed(due: Date, hasTime: Bool, days: Int = 1, now: Date, calendar: Calendar = .current) -> Date {
        if hasTime {
            var next = calendar.date(byAdding: .day, value: days, to: due)!
            while next <= now {
                next = calendar.date(byAdding: .day, value: 1, to: next)!
            }
            return next
        }
        let base = max(calendar.startOfDay(for: due), calendar.startOfDay(for: now))
        return calendar.date(byAdding: .day, value: days, to: base)!
    }
}

public enum DueText {
    static let weekdays = ["周日", "周一", "周二", "周三", "周四", "周五", "周六"]

    public static func dayOffset(_ date: Date, from now: Date, calendar: Calendar = .current) -> Int {
        calendar.dateComponents([.day], from: calendar.startOfDay(for: now), to: calendar.startOfDay(for: date)).day ?? 0
    }

    public static func isOverdue(due: Date, hasTime: Bool, now: Date, calendar: Calendar = .current) -> Bool {
        hasTime ? due < now : calendar.startOfDay(for: due) < calendar.startOfDay(for: now)
    }

    /// 例如「今天 15:00」「明天」「周五」「10月1日」「2 天前」。
    public static func describe(due: Date, hasTime: Bool, now: Date, calendar: Calendar = .current) -> String {
        let offset = dayOffset(due, from: now, calendar: calendar)
        let day: String = switch offset {
        case 0: "今天"
        case 1: "明天"
        case 2: "后天"
        case -1: "昨天"
        case ..<(-1): "\(-offset) 天前"
        case 3...6: weekdays[calendar.component(.weekday, from: due) - 1]
        default: fullDate(due, now: now, calendar: calendar)
        }
        return hasTime ? "\(day) \(time(due, calendar: calendar))" : day
    }

    public static func monthDay(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.month, .day], from: date)
        return "\(c.month!)/\(c.day!)"
    }

    public static func time(_ date: Date, calendar: Calendar = .current) -> String {
        let c = calendar.dateComponents([.hour, .minute], from: date)
        return String(format: "%02d:%02d", c.hour!, c.minute!)
    }

    static func fullDate(_ date: Date, now: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: date)
        if c.year == calendar.component(.year, from: now) {
            return "\(c.month!)月\(c.day!)日"
        }
        return "\(c.year!)年\(c.month!)月\(c.day!)日"
    }
}

/// 列表里的时间分组。
public enum EntryGroup: Int, CaseIterable, Sendable, Comparable {
    case overdue
    case today
    case tomorrow
    case thisWeek
    case later

    public var title: String {
        switch self {
        case .overdue: "逾期"
        case .today: "今天"
        case .tomorrow: "明天"
        case .thisWeek: "7 天内"
        case .later: "以后"
        }
    }

    public static func of(due: Date, hasTime: Bool, now: Date, calendar: Calendar = .current) -> EntryGroup {
        if DueText.isOverdue(due: due, hasTime: hasTime, now: now, calendar: calendar) { return .overdue }
        switch DueText.dayOffset(due, from: now, calendar: calendar) {
        case 0: return .today
        case 1: return .tomorrow
        case 2...7: return .thisWeek
        default: return .later
        }
    }

    public static func < (lhs: EntryGroup, rhs: EntryGroup) -> Bool { lhs.rawValue < rhs.rawValue }
}
