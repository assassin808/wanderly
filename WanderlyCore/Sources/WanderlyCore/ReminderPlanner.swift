import Foundation

public struct ReminderSettings: Codable, Equatable, Sendable {
    /// 早上提醒今天到期的事，从 0 点算起的分钟数。
    public var morningMinute: Int
    /// 晚间整理：提醒完善速记、确认是否做完。
    public var eveningMinute: Int
    /// 周回顾在星期几的晚间整理里出现（1 = 周日 … 7 = 周六，0 = 关闭）。
    public var reviewWeekday: Int
    /// 有具体时间的事，到点后多久问「做完了吗」。
    public var checkDelayMinutes: Int

    public init(morningMinute: Int, eveningMinute: Int, reviewWeekday: Int, checkDelayMinutes: Int) {
        self.morningMinute = morningMinute
        self.eveningMinute = eveningMinute
        self.reviewWeekday = reviewWeekday
        self.checkDelayMinutes = checkDelayMinutes
    }

    public static let `default` = ReminderSettings(morningMinute: 9 * 60, eveningMinute: 21 * 60 + 30, reviewWeekday: 1, checkDelayMinutes: 60)
}

public struct PlannedNotification: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// 早上：今天到期的事。
        case morning
        /// 晚上：待完善、逾期、周回顾。
        case evening
        /// 有具体时间的事到点了。
        case due
        /// 单条确认：做完了吗？
        case check
    }

    public var id: String
    public var kind: Kind
    public var fireDate: Date
    public var title: String
    public var body: String
    public var entryID: UUID?
}

/// 根据当前数据算出未来几天要发的本地通知。每次数据变化后整体重排。
public enum ReminderPlanner {
    /// iOS 最多保留 64 条待发本地通知，留一点余量。
    public static let maxPending = 60

    public static func plan(
        entries: [EntrySnapshot],
        settings: ReminderSettings,
        now: Date,
        calendar: Calendar = .current,
        days: Int = 7
    ) -> [PlannedNotification] {
        let active = entries.filter { $0.state.isActive }
        let today = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: days, to: today)!
        var result: [PlannedNotification] = []

        for offset in 0..<days {
            let day = calendar.date(byAdding: .day, value: offset, to: today)!
            let key = dayKey(day, calendar: calendar)

            let morning = at(day, minute: settings.morningMinute, calendar: calendar)
            if morning > now {
                let dueToday = active
                    .filter { calendar.isDate($0.due, inSameDayAs: day) }
                    .sorted { ($0.due, $0.title) < ($1.due, $1.title) }
                if !dueToday.isEmpty {
                    result.append(PlannedNotification(
                        id: "morning-\(key)", kind: .morning, fireDate: morning,
                        title: "今天有 \(dueToday.count) 件事到期",
                        body: summary(dueToday.map(\.title)), entryID: nil))
                }
            }

            let evening = at(day, minute: settings.eveningMinute, calendar: calendar)
            if evening > now {
                var lines: [String] = []
                let rough = active.filter { $0.state == .rough }.count
                if rough > 0 { lines.append("\(rough) 条速记还没完善") }
                let overdue = active.filter { calendar.startOfDay(for: $0.due) < day }.count
                if overdue > 0 { lines.append("\(overdue) 件事已经过了截止日") }
                if settings.reviewWeekday == calendar.component(.weekday, from: day) {
                    let farAway = calendar.date(byAdding: .day, value: 7, to: day)!
                    let later = active.filter { $0.due >= farAway }.count
                    if later > 0 { lines.append("周回顾：还有 \(later) 件远一点的事，过一眼") }
                }
                if !lines.isEmpty {
                    result.append(PlannedNotification(
                        id: "evening-\(key)", kind: .evening, fireDate: evening,
                        title: "晚间整理", body: lines.joined(separator: "\n"), entryID: nil))
                }
            }
        }

        for entry in active {
            if entry.hasTime, entry.due > now, entry.due < horizon {
                result.append(PlannedNotification(
                    id: "due-\(entry.id.uuidString)", kind: .due, fireDate: entry.due,
                    title: entry.title, body: "到时间了", entryID: entry.id))
            }

            var check = entry.hasTime
                ? entry.due.addingTimeInterval(TimeInterval(settings.checkDelayMinutes * 60))
                : at(calendar.startOfDay(for: entry.due), minute: settings.eveningMinute, calendar: calendar)
            if check <= now {
                // 已经过了确认时间还没处理：下一个晚上再问一次。
                check = nextEvening(after: now, settings: settings, calendar: calendar)
            }
            if check < horizon {
                result.append(PlannedNotification(
                    id: "check-\(entry.id.uuidString)", kind: .check, fireDate: check,
                    title: "做完了吗？", body: entry.title, entryID: entry.id))
            }
        }

        result.sort { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        return Array(result.prefix(maxPending))
    }

    static func at(_ day: Date, minute: Int, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day)!
    }

    static func nextEvening(after now: Date, settings: ReminderSettings, calendar: Calendar) -> Date {
        let tonight = at(calendar.startOfDay(for: now), minute: settings.eveningMinute, calendar: calendar)
        if tonight > now { return tonight }
        return calendar.date(byAdding: .day, value: 1, to: tonight)!
    }

    static func dayKey(_ day: Date, calendar: Calendar) -> String {
        let c = calendar.dateComponents([.year, .month, .day], from: day)
        return String(format: "%04d-%02d-%02d", c.year!, c.month!, c.day!)
    }

    static func summary(_ titles: [String]) -> String {
        let head = titles.prefix(3).joined(separator: "、")
        return titles.count > 3 ? "\(head) 等 \(titles.count) 件" : head
    }
}
