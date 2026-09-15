import Foundation

public struct DetectedDue: Equatable, Sendable {
    public var date: Date
    public var hasTime: Bool

    public init(date: Date, hasTime: Bool) {
        self.date = date
        self.hasTime = hasTime
    }
}

/// 从速记原文里识别截止时间，例如「周五下午三点」「明天」「9月20日」「下周一 10:30」「tomorrow 3pm」。
public enum DueParser {
    public static func parse(_ text: String, now: Date, calendar: Calendar = .current) -> DetectedDue? {
        let today = calendar.startOfDay(for: now)
        let day = matchDay(in: text, today: today, calendar: calendar)
        guard let time = matchTime(in: text) else {
            return day.map { DetectedDue(date: $0.date, hasTime: false) }
        }
        let hour = time.isAbsolute ? time.hour : adjust(hour: time.hour, period: time.period ?? day?.period)
        guard (0...23).contains(hour), (0...59).contains(time.minute) else {
            return day.map { DetectedDue(date: $0.date, hasTime: false) }
        }
        var date = calendar.date(bySettingHour: hour, minute: time.minute, second: 0, of: day?.date ?? today)!
        // 只说了几点、而且今天这个时间已经过了，就当作明天。
        if day == nil, date <= now {
            date = calendar.date(byAdding: .day, value: 1, to: date)!
        }
        return DetectedDue(date: date, hasTime: true)
    }

    enum Period: Equatable {
        case lateNight, morning, noon, afternoon, evening
    }

    // MARK: - 日期

    struct DayMatch: Equatable {
        let date: Date
        let period: Period?
    }

    static func matchDay(in text: String, today: Date, calendar: Calendar) -> DayMatch? {
        if let groups = firstMatch(#"(\d{1,2})\s*月\s*(\d{1,2})\s*[日号號]?"#, in: text)
            ?? firstMatch(#"(?<![\d/])(\d{1,2})/(\d{1,2})(?![\d/])"#, in: text),
           let month = Int(groups[1] ?? ""), let dayOfMonth = Int(groups[2] ?? ""),
           let date = explicitDate(month: month, day: dayOfMonth, today: today, calendar: calendar) {
            return DayMatch(date: date, period: nil)
        }

        if let groups = firstMatch(#"(下个?|这个?|這個?|本)?\s*(?:周末|週末)"#, in: text) {
            let shortcut: DueShortcut = (groups[1] ?? "").hasPrefix("下") ? .nextWeekend : .weekend
            return DayMatch(date: shortcut.date(from: today, calendar: calendar), period: nil)
        }

        if let groups = firstMatch(#"(下下个?|下个?|这个?|這個?|本)?\s*(?:周|週|星期|礼拜|禮拜)\s*([一二三四五六日天1-7])"#, in: text),
           let target = weekdayIndex(groups[2] ?? "") {
            // 周一为 0，周日为 6。
            let todayIndex = (calendar.component(.weekday, from: today) + 5) % 7
            let prefix = groups[1] ?? ""
            let offset: Int
            if prefix.hasPrefix("下下") {
                offset = 14 - todayIndex + target
            } else if prefix.hasPrefix("下") {
                offset = 7 - todayIndex + target
            } else if prefix.isEmpty {
                offset = (target - todayIndex + 7) % 7
            } else {
                offset = target - todayIndex
            }
            return DayMatch(date: calendar.date(byAdding: .day, value: offset, to: today)!, period: nil)
        }

        if let groups = firstMatch(#"(大后天|后天|後天|明天|明早|明晚|今天|今早|今晚|tomorrow|today|tonight)"#, in: text, options: .caseInsensitive),
           let word = groups[1]?.lowercased() {
            let offset: Int = switch word {
            case "大后天": 3
            case "后天", "後天": 2
            case "明天", "明早", "明晚", "tomorrow": 1
            default: 0
            }
            let period: Period? = switch word {
            case "今晚", "明晚", "tonight": .evening
            case "今早", "明早": .morning
            default: nil
            }
            return DayMatch(date: calendar.date(byAdding: .day, value: offset, to: today)!, period: period)
        }

        return nil
    }

    static func explicitDate(month: Int, day: Int, today: Date, calendar: Calendar) -> Date? {
        let year = calendar.component(.year, from: today)
        var components = DateComponents(year: year, month: month, day: day)
        // 2月30日这类日期会被 Calendar 顺延到下个月，这里排除掉。
        guard let date = calendar.date(from: components), calendar.component(.month, from: date) == month else { return nil }
        if date >= today { return date }
        components.year = year + 1
        return calendar.date(from: components)
    }

    static func weekdayIndex(_ value: String) -> Int? {
        switch value {
        case "一", "1": 0
        case "二", "2": 1
        case "三", "3": 2
        case "四", "4": 3
        case "五", "5": 4
        case "六", "6": 5
        case "日", "天", "7": 6
        default: nil
        }
    }

    // MARK: - 时间

    struct TimeMatch {
        let hour: Int
        let minute: Int
        let period: Period?
        /// 已经是 24 小时制，不需要再按上下午推断。
        let isAbsolute: Bool
    }

    static let periodPattern = #"(凌晨|早上|早晨|上午|中午|下午|傍晚|晚上|今早|今晚|明早|明晚)?\s*"#

    static func matchTime(in text: String) -> TimeMatch? {
        if let groups = firstMatch(#"(?<!\d)(\d{1,2})(?::(\d{2}))?\s*(am|pm)(?![a-z])"#, in: text, options: .caseInsensitive),
           let hour = Int(groups[1] ?? ""), (1...12).contains(hour) {
            let isPM = groups[3]?.lowercased() == "pm"
            return TimeMatch(hour: hour % 12 + (isPM ? 12 : 0), minute: Int(groups[2] ?? "") ?? 0, period: nil, isAbsolute: true)
        }

        if let groups = firstMatch(periodPattern + #"(\d{1,2})[:：](\d{2})"#, in: text),
           let hour = Int(groups[2] ?? ""), let minute = Int(groups[3] ?? "") {
            let spokenPeriod = groups[1].flatMap(period(from:))
            return TimeMatch(hour: hour, minute: minute, period: spokenPeriod, isAbsolute: spokenPeriod == nil && hour >= 13)
        }

        if let groups = firstMatch(periodPattern + #"(\d{1,2}|[零一二两三四五六七八九十]{1,3})\s*(?:点|點|时)(半|一刻|三刻|(\d{1,2})\s*分?|([零一二两三四五六七八九十]{1,3})\s*分)?"#, in: text),
           let hour = number(groups[2] ?? "") {
            let minute: Int
            switch groups[3] {
            case "半": minute = 30
            case "一刻": minute = 15
            case "三刻": minute = 45
            default: minute = number(groups[4] ?? groups[5] ?? "") ?? 0
            }
            let spokenPeriod = groups[1].flatMap(period(from:))
            return TimeMatch(hour: hour, minute: minute, period: spokenPeriod, isAbsolute: spokenPeriod == nil && hour >= 13)
        }

        return nil
    }

    static func period(from word: String) -> Period? {
        switch word {
        case "凌晨": .lateNight
        case "早上", "早晨", "上午", "今早", "明早": .morning
        case "中午": .noon
        case "下午": .afternoon
        case "傍晚", "晚上", "今晚", "明晚": .evening
        default: nil
        }
    }

    /// 把口语里的钟点换成 24 小时制。没说上下午时，1–6 点按下午算（「3点开会」一般是 15:00）。
    static func adjust(hour: Int, period: Period?) -> Int {
        switch period {
        case .afternoon?, .evening?: hour < 12 ? hour + 12 : hour
        case .noon?: hour < 11 ? hour + 12 : hour
        case .lateNight?: hour == 12 ? 0 : hour
        case .morning?: hour
        case nil: (1...6).contains(hour) ? hour + 12 : hour
        }
    }

    /// 阿拉伯数字或「三」「十一」「二十三」这类中文数字。
    static func number(_ value: String) -> Int? {
        if let number = Int(value) { return number }
        let digits: [Character: Int] = ["零": 0, "一": 1, "二": 2, "两": 2, "三": 3, "四": 4, "五": 5, "六": 6, "七": 7, "八": 8, "九": 9]
        if let ten = value.firstIndex(of: "十") {
            let before = value[value.startIndex..<ten]
            let after = value[value.index(after: ten)...]
            let tens = before.isEmpty ? 1 : (before.count == 1 ? digits[before.first!] : nil)
            let ones = after.isEmpty ? 0 : (after.count == 1 ? digits[after.first!] : nil)
            guard let tens, let ones else { return nil }
            return tens * 10 + ones
        }
        guard value.count == 1, let digit = digits[value.first!] else { return nil }
        return digit
    }

    /// 第一个匹配的所有捕获组（下标 0 是整体匹配），没参与匹配的组为 nil。
    static func firstMatch(_ pattern: String, in text: String, options: NSRegularExpression.Options = []) -> [String?]? {
        guard let regex = try? NSRegularExpression(pattern: pattern, options: options) else { return nil }
        let source = text as NSString
        guard let match = regex.firstMatch(in: text, range: NSRange(location: 0, length: source.length)) else { return nil }
        return (0..<match.numberOfRanges).map { index in
            let range = match.range(at: index)
            return range.location == NSNotFound ? nil : source.substring(with: range)
        }
    }
}
