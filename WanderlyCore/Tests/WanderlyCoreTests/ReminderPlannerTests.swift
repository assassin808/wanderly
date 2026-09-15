import Foundation
import Testing
@testable import WanderlyCore

struct ReminderPlannerTests {
    /// 周一上午 10 点。默认设置：早上 9:00、晚上 20:00、记下 2 小时后第一次提醒。
    let now = d(2026, 9, 14, 10)

    func plan(_ entries: [EntrySnapshot], now: Date? = nil) -> [PlannedNotification] {
        ReminderPlanner.plan(entries: entries, settings: .default, now: now ?? self.now, calendar: cal)
    }

    func rough(_ title: String = "速记", urgency: Urgency = .urgent, created: Date? = nil) -> EntrySnapshot {
        EntrySnapshot(title: title, state: .rough, urgency: urgency, hasDue: false, createdAt: created ?? d(2026, 9, 14, 9, 30))
    }

    func days(of notifications: [PlannedNotification], kind: PlannedNotification.Kind) -> [Date] {
        notifications.filter { $0.kind == kind }.map(\.fireDate)
    }

    // MARK: 完善提醒

    @Test func firstNudgeComesTwoHoursAfterCapture() throws {
        var entry = rough("给导师发邮件", urgency: .soon)
        entry.prompt = "想让导师帮你看什么？"
        let first = try #require(plan([entry]).first { $0.id == "refine-\(entry.id.uuidString)" })
        #expect(first.kind == .refine)
        #expect(first.fireDate == d(2026, 9, 14, 11, 30))
        #expect(first.title == "去完善：给导师发邮件")
        #expect(first.body == "AI 问：想让导师帮你看什么？")
        #expect(first.entryID == entry.id)
    }

    @Test func firstNudgeWaitsUntilMorning() {
        let entry = rough(created: d(2026, 9, 14, 21, 30))
        let p = plan([entry], now: d(2026, 9, 14, 21, 40))
        #expect(p.first { $0.id == "refine-\(entry.id.uuidString)" }?.fireDate == d(2026, 9, 15, 9))
    }

    @Test func urgentRoughEntryIsNudgedEveryEvening() {
        let entry = rough(urgency: .urgent)
        let evenings = days(of: plan([entry]), kind: .refine).filter { cal.component(.hour, from: $0) == 20 }
        #expect(evenings.prefix(3) == [d(2026, 9, 15, 20), d(2026, 9, 16, 20), d(2026, 9, 17, 20)])
    }

    @Test func soonEveryOtherDayAndLaterWeekly() {
        let soon = rough("这几天", urgency: .soon)
        #expect(days(of: plan([soon]), kind: .refine).dropFirst().prefix(2) == [d(2026, 9, 16, 20), d(2026, 9, 18, 20)])

        let later = rough("不急", urgency: .later)
        #expect(days(of: plan([later]), kind: .refine) == [d(2026, 9, 14, 11, 30), d(2026, 9, 21, 20)])
    }

    @Test func activityRestartsTheSchedule() {
        var entry = rough(urgency: .urgent, created: d(2026, 9, 13, 9, 30))
        entry.lastActivityAt = d(2026, 9, 14, 9, 50)
        let refines = days(of: plan([entry]), kind: .refine)
        #expect(refines.first == d(2026, 9, 15, 20))
    }

    @Test func snoozeSendsOneNudgeThenContinues() {
        var entry = rough(urgency: .urgent)
        entry.snoozedUntil = d(2026, 9, 14, 13)
        let refines = days(of: plan([entry]), kind: .refine)
        #expect(refines.prefix(2) == [d(2026, 9, 14, 13), d(2026, 9, 15, 20)])
    }

    @Test func archiveIsNeverReminded() {
        let p = plan([
            rough("只是存一下", urgency: .archive),
            EntrySnapshot(title: "资料", state: .open, urgency: .archive, hasDue: false),
        ])
        #expect(p.isEmpty)
    }

    @Test func severalNudgesInOneEveningBecomeADigest() throws {
        let a = rough("A")
        let b = rough("B")
        let p = plan([a, b])
        let digest = try #require(p.first { $0.id == "refines-2026-09-15" })
        #expect(digest.kind == .refineDigest)
        #expect(digest.title == "有 2 条等你完善")
        #expect(digest.body == "A、B")
        #expect(!p.contains { $0.id == "refine-\(a.id.uuidString)-2026-09-15" })
    }

    // MARK: 没有截止日期的事

    @Test func openEntriesWithoutDueGetCheckIns() throws {
        let entry = EntrySnapshot(title: "读论文", state: .open, urgency: .soon, hasDue: false,
                                  createdAt: d(2026, 9, 13), refinedAt: d(2026, 9, 14, 9))
        let checkIns = plan([entry]).filter { $0.kind == .checkIn }
        let first = try #require(checkIns.first)
        #expect(first.fireDate == d(2026, 9, 16, 9))
        #expect(first.title == "还在进行吗？")
        #expect(first.body == "读论文")
    }

    @Test func checkInsInOneMorningBecomeADigest() {
        let entries = ["甲", "乙"].map {
            EntrySnapshot(title: $0, state: .open, urgency: .soon, hasDue: false, createdAt: d(2026, 9, 14, 9))
        }
        #expect(plan(entries).first { $0.id == "checkins-2026-09-16" }?.title == "这 2 件事还在进行吗？")
    }

    @Test func waterPromptIsSentTonight() {
        let fresh = EntrySnapshot(title: "想法", state: .open, urgency: .later, hasDue: false, createdAt: d(2026, 9, 10),
                                  lastActivityAt: d(2026, 9, 11), prompt: "如果只做一个实验，你会做什么？", promptAt: d(2026, 9, 14, 9))
        let water = plan([fresh]).first { $0.kind == .water }
        #expect(water?.fireDate == d(2026, 9, 14, 20))
        #expect(water?.title == "浇水：想法")
        #expect(water?.body == "如果只做一个实验，你会做什么？")

        var answered = fresh
        answered.lastActivityAt = d(2026, 9, 14, 9, 30)
        #expect(!plan([answered]).contains { $0.kind == .water })
    }

    // MARK: 有截止日期的事

    @Test func timedEntryFiresAtTimeThenAsksLater() {
        let entry = EntrySnapshot(title: "组会", due: d(2026, 9, 14, 15), hasTime: true, state: .open, hasDue: true, createdAt: d(2026, 9, 14, 8))
        let p = plan([entry])
        #expect(p.first { $0.kind == .due }?.fireDate == d(2026, 9, 14, 15))
        #expect(p.first { $0.kind == .check }?.fireDate == d(2026, 9, 14, 16))
        #expect(!p.contains { $0.kind == .checkIn })
    }

    @Test func dueTodayMorningDigestAndEveningCheck() {
        let entry = EntrySnapshot(title: "交报销", due: d(2026, 9, 16), state: .open, hasDue: true, createdAt: d(2026, 9, 14, 8))
        let p = plan([entry])
        #expect(p.first { $0.id == "morning-2026-09-16" }?.fireDate == d(2026, 9, 16, 9))
        #expect(p.first { $0.kind == .check }?.fireDate == d(2026, 9, 16, 20))
    }

    @Test func overdueEntryIsCheckedNextEvening() {
        let entry = EntrySnapshot(title: "交报销", due: d(2026, 9, 12), state: .open, hasDue: true, createdAt: d(2026, 9, 10))
        #expect(plan([entry]).first { $0.kind == .check }?.fireDate == d(2026, 9, 14, 20))
        #expect(plan([entry], now: d(2026, 9, 14, 21)).first { $0.kind == .check }?.fireDate == d(2026, 9, 15, 20))
    }

    // MARK: 整体

    @Test func closedEntriesAreIgnored() {
        let p = plan([
            EntrySnapshot(title: "a", state: .done, hasDue: false),
            EntrySnapshot(title: "b", due: d(2026, 9, 15), state: .dropped),
        ])
        #expect(p.isEmpty)
    }

    @Test func keepAliveComesAfterEverythingElse() throws {
        let p = plan([rough(urgency: .later)])
        let keepAlive = try #require(p.last)
        #expect(keepAlive.kind == .keepAlive)
        #expect(p.filter { $0.kind == .keepAlive }.count == 1)
        #expect(p.dropLast().allSatisfy { $0.fireDate < keepAlive.fireDate })
    }

    @Test func pendingCountIsCappedAndSorted() {
        let entries = (0..<100).map { rough("\($0)") }
        let p = plan(entries)
        #expect(p.count == ReminderPlanner.maxPending)
        #expect(zip(p, p.dropFirst()).allSatisfy { $0.fireDate <= $1.fireDate })
    }
}
