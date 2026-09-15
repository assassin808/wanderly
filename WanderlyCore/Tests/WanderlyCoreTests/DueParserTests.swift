import Foundation
import Testing
@testable import WanderlyCore

struct DueParserTests {
    /// 周一上午 10 点。
    let now = d(2026, 9, 14, 10)

    func parse(_ text: String, now: Date? = nil) -> DetectedDue? {
        DueParser.parse(text, now: now ?? self.now, calendar: cal)
    }

    @Test func weekdayWithAfternoonTime() {
        #expect(parse("周五下午三点和导师开会") == DetectedDue(date: d(2026, 9, 18, 15), hasTime: true))
    }

    @Test func relativeDays() {
        #expect(parse("明天交报销") == DetectedDue(date: d(2026, 9, 15), hasTime: false))
        #expect(parse("后天上午9点体检") == DetectedDue(date: d(2026, 9, 16, 9), hasTime: true))
        #expect(parse("今晚八点半打电话") == DetectedDue(date: d(2026, 9, 14, 20, 30), hasTime: true))
        #expect(parse("大后天") == DetectedDue(date: d(2026, 9, 17), hasTime: false))
    }

    @Test func weeks() {
        #expect(parse("下周一 10:30 组会") == DetectedDue(date: d(2026, 9, 21, 10, 30), hasTime: true))
        #expect(parse("这周三交作业") == DetectedDue(date: d(2026, 9, 16), hasTime: false))
        #expect(parse("周一") == DetectedDue(date: d(2026, 9, 14), hasTime: false))
        #expect(parse("星期天去超市") == DetectedDue(date: d(2026, 9, 20), hasTime: false))
        #expect(parse("周末爬山") == DetectedDue(date: d(2026, 9, 20), hasTime: false))
        #expect(parse("下周末搬家") == DetectedDue(date: d(2026, 9, 27), hasTime: false))
    }

    @Test func explicitDates() {
        #expect(parse("9月20日截稿") == DetectedDue(date: d(2026, 9, 20), hasTime: false))
        #expect(parse("1月3号续签证") == DetectedDue(date: d(2027, 1, 3), hasTime: false))
        #expect(parse("10/15 交 proposal") == DetectedDue(date: d(2026, 10, 15), hasTime: false))
        #expect(parse("2月30日") == nil)
    }

    @Test func timeOnly() {
        #expect(parse("3点开会") == DetectedDue(date: d(2026, 9, 14, 15), hasTime: true))
        #expect(parse("3点开会", now: d(2026, 9, 14, 16)) == DetectedDue(date: d(2026, 9, 15, 15), hasTime: true))
        #expect(parse("中午12点吃饭") == DetectedDue(date: d(2026, 9, 14, 12), hasTime: true))
        #expect(parse("十一点半 call") == DetectedDue(date: d(2026, 9, 14, 11, 30), hasTime: true))
        #expect(parse("周五下午3点 2楼会议室") == DetectedDue(date: d(2026, 9, 18, 15), hasTime: true))
    }

    @Test func english() {
        #expect(parse("call mom tomorrow 3pm") == DetectedDue(date: d(2026, 9, 15, 15), hasTime: true))
        #expect(parse("明天9:00am站会") == DetectedDue(date: d(2026, 9, 15, 9), hasTime: true))
    }

    @Test func upcomingIncludesDateOnlyToday() {
        #expect(DetectedDue(date: d(2026, 9, 14), hasTime: false).isUpcoming(now: now, calendar: cal))
        #expect(!DetectedDue(date: d(2026, 9, 13), hasTime: false).isUpcoming(now: now, calendar: cal))
        #expect(!DetectedDue(date: d(2026, 9, 14, 9), hasTime: true).isUpcoming(now: now, calendar: cal))
        #expect(DetectedDue(date: d(2026, 9, 14, 11), hasTime: true).isUpcoming(now: now, calendar: cal))
    }

    @Test func nothingToDetect() {
        #expect(parse("买咖啡豆") == nil)
        #expect(parse("idea：让 agent 自己写 eval") == nil)
        #expect(parse("25点") == nil)
    }
}
