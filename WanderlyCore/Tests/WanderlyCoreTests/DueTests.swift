import Foundation
import Testing
@testable import WanderlyCore

let cal: Calendar = {
    var c = Calendar(identifier: .gregorian)
    c.timeZone = TimeZone(identifier: "America/New_York")!
    c.locale = Locale(identifier: "zh_CN")
    return c
}()

func d(_ year: Int, _ month: Int, _ day: Int, _ hour: Int = 0, _ minute: Int = 0) -> Date {
    cal.date(from: DateComponents(year: year, month: month, day: day, hour: hour, minute: minute))!
}

struct DueTests {
    /// 2026-09-14 是周一。
    let now = d(2026, 9, 14, 10)

    @Test func shortcuts() {
        #expect(DueShortcut.today.date(from: now, calendar: cal) == d(2026, 9, 14))
        #expect(DueShortcut.tomorrow.date(from: now, calendar: cal) == d(2026, 9, 15))
        #expect(DueShortcut.weekend.date(from: now, calendar: cal) == d(2026, 9, 20))
        #expect(DueShortcut.nextWeekend.date(from: now, calendar: cal) == d(2026, 9, 27))
        #expect(DueShortcut.weekend.label(from: now, calendar: cal) == "周末 9/20")
    }

    @Test func weekendOnSundayIsToday() {
        let sunday = d(2026, 9, 20, 8)
        #expect(DueShortcut.weekend.date(from: sunday, calendar: cal) == d(2026, 9, 20))
        #expect(DueShortcut.nextWeekend.date(from: sunday, calendar: cal) == d(2026, 9, 27))
    }

    @Test func matching() {
        #expect(DueShortcut.matching(due: d(2026, 9, 20), hasTime: false, now: now, calendar: cal) == .weekend)
        #expect(DueShortcut.matching(due: d(2026, 9, 20, 15), hasTime: true, now: now, calendar: cal) == nil)
        #expect(DueShortcut.matching(due: d(2026, 9, 17), hasTime: false, now: now, calendar: cal) == nil)
    }

    @Test func describe() {
        #expect(DueText.describe(due: d(2026, 9, 14, 15), hasTime: true, now: now, calendar: cal) == "今天 15:00")
        #expect(DueText.describe(due: d(2026, 9, 15), hasTime: false, now: now, calendar: cal) == "明天")
        #expect(DueText.describe(due: d(2026, 9, 18), hasTime: false, now: now, calendar: cal) == "周五")
        #expect(DueText.describe(due: d(2026, 10, 1), hasTime: false, now: now, calendar: cal) == "10月1日")
        #expect(DueText.describe(due: d(2027, 1, 3), hasTime: false, now: now, calendar: cal) == "2027年1月3日")
        #expect(DueText.describe(due: d(2026, 9, 12), hasTime: false, now: now, calendar: cal) == "2 天前")
    }

    @Test func snooze() {
        // 逾期的事推迟到明天，而不是原截止日的后一天。
        #expect(DueMath.snoozed(due: d(2026, 9, 12), hasTime: false, now: now, calendar: cal) == d(2026, 9, 15))
        #expect(DueMath.snoozed(due: d(2026, 9, 20), hasTime: false, now: now, calendar: cal) == d(2026, 9, 21))
        #expect(DueMath.snoozed(due: d(2026, 9, 14, 15), hasTime: true, now: now, calendar: cal) == d(2026, 9, 15, 15))
        #expect(DueMath.snoozed(due: d(2026, 9, 10, 15), hasTime: true, now: now, calendar: cal) == d(2026, 9, 14, 15))
    }

    @Test func groups() {
        #expect(EntryGroup.of(due: d(2026, 9, 14, 9), hasTime: true, now: now, calendar: cal) == .overdue)
        #expect(EntryGroup.of(due: d(2026, 9, 14), hasTime: false, now: now, calendar: cal) == .today)
        #expect(EntryGroup.of(due: d(2026, 9, 15, 9), hasTime: true, now: now, calendar: cal) == .tomorrow)
        #expect(EntryGroup.of(due: d(2026, 9, 21), hasTime: false, now: now, calendar: cal) == .thisWeek)
        #expect(EntryGroup.of(due: d(2026, 9, 22), hasTime: false, now: now, calendar: cal) == .later)
    }
}
