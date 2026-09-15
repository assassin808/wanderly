import Foundation
import Testing
@testable import WanderlyCore

struct ReminderPlannerTests {
    /// 周一上午 10 点。
    let now = d(2026, 9, 14, 10)

    func plan(_ entries: [EntrySnapshot], now: Date? = nil) -> [PlannedNotification] {
        ReminderPlanner.plan(entries: entries, settings: .default, now: now ?? self.now, calendar: cal)
    }

    @Test func roughEntryGetsRefineNudgeMorningDigestAndCheck() throws {
        let entry = EntrySnapshot(title: "给导师发邮件", due: d(2026, 9, 16))
        let p = plan([entry])

        let evening = try #require(p.first { $0.id == "evening-2026-09-14" })
        #expect(evening.fireDate == d(2026, 9, 14, 21, 30))
        #expect(evening.body.contains("1 条速记还没完善"))

        let morning = try #require(p.first { $0.id == "morning-2026-09-16" })
        #expect(morning.fireDate == d(2026, 9, 16, 9))
        #expect(morning.body == "给导师发邮件")

        let check = try #require(p.first { $0.kind == .check })
        #expect(check.fireDate == d(2026, 9, 16, 21, 30))
        #expect(check.entryID == entry.id)

        // 今天早上的提醒时间已经过了。
        #expect(!p.contains { $0.id == "morning-2026-09-14" })
    }

    @Test func timedEntryFiresAtTimeThenAsksLater() {
        let entry = EntrySnapshot(title: "组会", due: d(2026, 9, 14, 15), hasTime: true, state: .open)
        let p = plan([entry])
        #expect(p.first { $0.kind == .due }?.fireDate == d(2026, 9, 14, 15))
        #expect(p.first { $0.kind == .check }?.fireDate == d(2026, 9, 14, 16))
        // 已完善的事不会触发「待完善」提醒，今晚也没有逾期。
        #expect(!p.contains { $0.id == "evening-2026-09-14" })
    }

    @Test func overdueEntryIsCheckedNextEvening() {
        let entry = EntrySnapshot(title: "交报销", due: d(2026, 9, 12), state: .open)

        let p = plan([entry])
        #expect(p.first { $0.kind == .check }?.fireDate == d(2026, 9, 14, 21, 30))
        #expect(p.first { $0.id == "evening-2026-09-14" }?.body.contains("1 件事已经过了截止日") == true)

        let late = plan([entry], now: d(2026, 9, 14, 22))
        #expect(late.first { $0.kind == .check }?.fireDate == d(2026, 9, 15, 21, 30))
        #expect(!late.contains { $0.id == "evening-2026-09-14" })
    }

    @Test func closedEntriesAreIgnored() {
        let p = plan([
            EntrySnapshot(title: "a", due: d(2026, 9, 15), state: .done),
            EntrySnapshot(title: "b", due: d(2026, 9, 15), state: .dropped),
        ])
        #expect(p.isEmpty)
    }

    @Test func sundayEveningIncludesWeeklyReview() {
        let entry = EntrySnapshot(title: "写 related work", due: d(2026, 10, 10), state: .open)
        let p = plan([entry])
        #expect(p.first { $0.id == "evening-2026-09-20" }?.body.contains("周回顾") == true)
        #expect(!p.contains { $0.id == "evening-2026-09-19" })
        // 截止日在 7 天之外，不会提前排确认通知。
        #expect(!p.contains { $0.kind == .check })
    }

    @Test func morningDigestSummarizesManyTitles() {
        let entries = ["a", "b", "c", "d"].map { EntrySnapshot(title: $0, due: d(2026, 9, 15)) }
        let morning = plan(entries).first { $0.id == "morning-2026-09-15" }
        #expect(morning?.title == "今天有 4 件事到期")
        #expect(morning?.body == "a、b、c 等 4 件")
    }

    @Test func pendingCountIsCappedAndSorted() {
        let entries = (0..<100).map { EntrySnapshot(title: "\($0)", due: d(2026, 9, 15, 12), hasTime: true) }
        let p = plan(entries)
        #expect(p.count == ReminderPlanner.maxPending)
        #expect(zip(p, p.dropFirst()).allSatisfy { $0.fireDate <= $1.fireDate })
    }

    @Test func keepAliveComesAfterEverythingElse() throws {
        let entry = EntrySnapshot(title: "组会", due: d(2026, 9, 15, 15), hasTime: true, state: .open)
        let p = plan([entry])
        let keepAlive = try #require(p.last)
        #expect(keepAlive.kind == .keepAlive)
        #expect(p.filter { $0.kind == .keepAlive }.count == 1)
        #expect(p.dropLast().allSatisfy { $0.fireDate < keepAlive.fireDate })
    }

    @Test func plansTwoWeeksAhead() {
        let entry = EntrySnapshot(title: "长期的事", due: d(2026, 9, 25), state: .open)
        let p = plan([entry])
        #expect(p.contains { $0.id == "morning-2026-09-25" })
        #expect(p.first { $0.kind == .check }?.fireDate == d(2026, 9, 25, 21, 30))
    }
}
