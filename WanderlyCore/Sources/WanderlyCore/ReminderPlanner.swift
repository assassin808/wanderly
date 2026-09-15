import Foundation

public struct ReminderSettings: Codable, Equatable, Sendable {
    /// 早上：今天到期的事、定期确认「还在进行吗」。从 0 点算起的分钟数。
    public var morningMinute: Int
    /// 晚上：定期提醒完善。
    public var eveningMinute: Int
    /// 记下后多久第一次提醒完善。
    public var firstNudgeMinutes: Int
    /// 有具体时间的事，到点后多久问「做完了吗」。
    public var checkDelayMinutes: Int

    /// 这个时间之后、早上提醒之前不打扰。
    public static let quietStartMinute = 22 * 60

    public init(morningMinute: Int, eveningMinute: Int, firstNudgeMinutes: Int, checkDelayMinutes: Int) {
        self.morningMinute = morningMinute
        self.eveningMinute = eveningMinute
        self.firstNudgeMinutes = firstNudgeMinutes
        self.checkDelayMinutes = checkDelayMinutes
    }

    public static let `default` = ReminderSettings(morningMinute: 9 * 60, eveningMinute: 20 * 60, firstNudgeMinutes: 120, checkDelayMinutes: 60)
}

public struct PlannedNotification: Equatable, Sendable {
    public enum Kind: String, Sendable {
        /// 早上：今天到期的事。
        case morning
        /// 有具体时间的事到点了。
        case due
        /// 有截止日期的事：做完了吗？
        case check
        /// 单条：去完善（回答 AI 的问题）。
        case refine
        /// 同一时段好几条等着完善，合成一条。
        case refineDigest
        /// 没有截止日期的事：还在进行吗？
        case checkIn
        case checkInDigest
        /// AI 对想法抛出了新问题（Beta 浇水）。
        case water
        /// 排在所有提醒之后：很久没打开 App 时提醒打开，让之后的提醒接上。
        case keepAlive
    }

    public var id: String
    public var kind: Kind
    public var fireDate: Date
    public var title: String
    public var body: String
    public var entryID: UUID?
}

/// 根据当前数据算出未来两周要发的本地通知。每次数据变化、App 回到前台或后台刷新时整体重排。
public enum ReminderPlanner {
    /// iOS 最多保留 64 条待发本地通知，留一点余量。
    public static let maxPending = 60

    public static func plan(
        entries: [EntrySnapshot],
        settings: ReminderSettings,
        now: Date,
        calendar: Calendar = .current,
        days: Int = 14
    ) -> [PlannedNotification] {
        let live = entries.filter { $0.state.isActive && $0.urgency != .archive }
        let today = calendar.startOfDay(for: now)
        let horizon = calendar.date(byAdding: .day, value: days, to: today)!
        let planDays = (0..<days).map { calendar.date(byAdding: .day, value: $0, to: today)! }
        var result: [PlannedNotification] = []

        // 有截止日期的事：早上汇总、到点提醒、过后确认。
        for day in planDays {
            let morning = at(day, minute: settings.morningMinute, calendar: calendar)
            guard morning > now else { continue }
            let dueToday = live
                .filter { $0.hasDue && calendar.isDate($0.due, inSameDayAs: day) }
                .sorted { ($0.due, $0.title) < ($1.due, $1.title) }
            if !dueToday.isEmpty {
                result.append(PlannedNotification(
                    id: "morning-\(dayKey(day, calendar: calendar))", kind: .morning, fireDate: morning,
                    title: "今天有 \(dueToday.count) 件事到期", body: summary(dueToday.map(\.title)), entryID: nil))
            }
        }
        for entry in live where entry.hasDue {
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
                check = nextSlot(after: now, minute: settings.eveningMinute, calendar: calendar)
            }
            if check < horizon {
                result.append(PlannedNotification(
                    id: "check-\(entry.id.uuidString)", kind: .check, fireDate: check,
                    title: "做完了吗？", body: entry.title, entryID: entry.id))
            }
        }

        // 没有截止日期也会定期提醒：待完善的在晚上，进行中的在早上。同一时段有几条就合成一条。
        var refineSlots: [Date: [EntrySnapshot]] = [:]
        var checkInSlots: [Date: [EntrySnapshot]] = [:]

        for entry in live {
            let snooze = entry.snoozedUntil.flatMap { $0 > now ? waking($0, settings: settings, calendar: calendar) : nil }

            if entry.state == .rough {
                let first = waking(entry.createdAt.addingTimeInterval(TimeInterval(settings.firstNudgeMinutes * 60)), settings: settings, calendar: calendar)
                // 趁记忆还新鲜：记下后不久提醒一次，除非用户已经动过这条或者约了稍后。
                if let single = snooze ?? (entry.lastActivityAt == nil ? first : nil), single > now, single < horizon {
                    result.append(refine(entry, at: single, id: "refine-\(entry.id.uuidString)"))
                }
                let base = [first, entry.lastActivityAt, snooze].compactMap { $0 }.max()!
                for slot in periodicSlots(base: base, interval: entry.urgency.intervalDays, minute: settings.eveningMinute, days: planDays, now: now, calendar: calendar) {
                    refineSlots[slot, default: []].append(entry)
                }
                continue
            }

            // 浇水问题出现后的第一个晚上提醒一次；那个时间过了就不再排，否则每次重排都会再提醒一遍。
            if let promptAt = entry.promptAt, let prompt = entry.prompt, promptAt > (entry.lastActivityAt ?? .distantPast) {
                let fire = nextSlot(after: promptAt, minute: settings.eveningMinute, calendar: calendar)
                if fire > now, fire < horizon {
                    result.append(PlannedNotification(
                        id: "water-\(entry.id.uuidString)", kind: .water, fireDate: fire,
                        title: "浇水：\(entry.title)", body: prompt, entryID: entry.id))
                }
            }

            guard !entry.hasDue else { continue }
            if let snooze, snooze < horizon {
                result.append(checkIn(entry, at: snooze, id: "checkin-\(entry.id.uuidString)"))
            }
            let base = [entry.refinedAt ?? entry.createdAt, entry.lastActivityAt, snooze].compactMap { $0 }.max()!
            for slot in periodicSlots(base: base, interval: entry.urgency.intervalDays, minute: settings.morningMinute, days: planDays, now: now, calendar: calendar) {
                checkInSlots[slot, default: []].append(entry)
            }
        }

        for (slot, group) in refineSlots {
            let key = dayKey(slot, calendar: calendar)
            if group.count == 1, let entry = group.first {
                result.append(refine(entry, at: slot, id: "refine-\(entry.id.uuidString)-\(key)"))
            } else {
                result.append(PlannedNotification(
                    id: "refines-\(key)", kind: .refineDigest, fireDate: slot,
                    title: "有 \(group.count) 条等你完善", body: summary(group.map(\.title).sorted()), entryID: nil))
            }
        }
        for (slot, group) in checkInSlots {
            let key = dayKey(slot, calendar: calendar)
            if group.count == 1, let entry = group.first {
                result.append(checkIn(entry, at: slot, id: "checkin-\(entry.id.uuidString)-\(key)"))
            } else {
                result.append(PlannedNotification(
                    id: "checkins-\(key)", kind: .checkInDigest, fireDate: slot,
                    title: "这 \(group.count) 件事还在进行吗？", body: summary(group.map(\.title).sorted()), entryID: nil))
            }
        }

        result.sort { ($0.fireDate, $0.id) < ($1.fireDate, $1.id) }
        var planned = Array(result.prefix(maxPending - 1))
        if !live.isEmpty {
            let last = planned.last?.fireDate ?? now
            planned.append(PlannedNotification(
                id: "keep-alive", kind: .keepAlive,
                fireDate: nextSlot(after: last, minute: settings.eveningMinute, calendar: calendar).addingTimeInterval(5 * 60),
                title: "Wanderly", body: "有一阵没打开 Wanderly 了，打开看一眼，之后的提醒才会接着排上。", entryID: nil))
        }
        return planned
    }

    static func refine(_ entry: EntrySnapshot, at date: Date, id: String) -> PlannedNotification {
        PlannedNotification(
            id: id, kind: .refine, fireDate: date, title: "去完善：\(entry.title)",
            body: entry.prompt.map { "AI 问：\($0)" } ?? "补几句，之后回来看才看得懂", entryID: entry.id)
    }

    static func checkIn(_ entry: EntrySnapshot, at date: Date, id: String) -> PlannedNotification {
        PlannedNotification(id: id, kind: .checkIn, fireDate: date, title: "还在进行吗？", body: entry.title, entryID: entry.id)
    }

    /// base 之后每隔 interval 天的固定时段。
    static func periodicSlots(base: Date, interval: Int?, minute: Int, days: [Date], now: Date, calendar: Calendar) -> [Date] {
        guard let interval else { return [] }
        let baseDay = calendar.startOfDay(for: base)
        return days.compactMap { day in
            let offset = calendar.dateComponents([.day], from: baseDay, to: day).day ?? 0
            let slot = at(day, minute: minute, calendar: calendar)
            guard offset > 0, offset % interval == 0, slot > now else { return nil }
            return slot
        }
    }

    /// 落在夜里的提醒挪到早上。
    static func waking(_ date: Date, settings: ReminderSettings, calendar: Calendar) -> Date {
        let day = calendar.startOfDay(for: date)
        let minute = calendar.component(.hour, from: date) * 60 + calendar.component(.minute, from: date)
        if minute < settings.morningMinute {
            return at(day, minute: settings.morningMinute, calendar: calendar)
        }
        if minute >= ReminderSettings.quietStartMinute {
            return at(calendar.date(byAdding: .day, value: 1, to: day)!, minute: settings.morningMinute, calendar: calendar)
        }
        return date
    }

    static func at(_ day: Date, minute: Int, calendar: Calendar) -> Date {
        calendar.date(bySettingHour: minute / 60, minute: minute % 60, second: 0, of: day)!
    }

    static func nextSlot(after date: Date, minute: Int, calendar: Calendar) -> Date {
        let slot = at(calendar.startOfDay(for: date), minute: minute, calendar: calendar)
        if slot > date { return slot }
        return calendar.date(byAdding: .day, value: 1, to: slot)!
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
