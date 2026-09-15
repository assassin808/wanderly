import Foundation
import Testing
@testable import WanderlyCore

struct WidgetSnapshotTests {
    let now = d(2026, 9, 14, 10)

    @Test func keepsLiveEntriesWithDeadlinesFirst() {
        let snapshot = WidgetSnapshot(entries: [
            EntrySnapshot(title: "不急的想法", state: .open, urgency: .later, hasDue: false),
            EntrySnapshot(title: "紧急的事", state: .rough, urgency: .urgent, hasDue: false),
            EntrySnapshot(title: "做完了", due: d(2026, 9, 13), state: .done),
            EntrySnapshot(title: "资料", state: .open, urgency: .archive, hasDue: false),
            EntrySnapshot(title: "周三截止", due: d(2026, 9, 16), state: .open),
        ])
        #expect(snapshot.items.map(\.title) == ["周三截止", "紧急的事", "不急的想法"])
        #expect(snapshot.roughCount == 1)
    }

    @Test func focusPrefersOverdueTodayAndUrgent() {
        let snapshot = WidgetSnapshot(entries: [
            EntrySnapshot(title: "逾期", due: d(2026, 9, 12), state: .open),
            EntrySnapshot(title: "紧急", state: .rough, urgency: .urgent, hasDue: false),
            EntrySnapshot(title: "以后", due: d(2026, 9, 30), state: .open),
        ])
        let focus = snapshot.focus(at: now, limit: 3, calendar: cal)
        #expect(focus.heading == "今天")
        #expect(focus.urgentCount == 2)
        #expect(focus.items.map(\.title) == ["逾期", "紧急"])
        #expect(focus.items[1].caption(now: now, calendar: cal) == "紧急 · 待完善")
    }

    @Test func focusFallsBackToUpcoming() {
        let snapshot = WidgetSnapshot(entries: [EntrySnapshot(title: "以后", state: .open, urgency: .later, hasDue: false)])
        let focus = snapshot.focus(at: now, limit: 3, calendar: cal)
        #expect(focus.heading == "接下来")
        #expect(focus.urgentCount == 0)
        #expect(WidgetSnapshot.empty.focus(at: now, limit: 3, calendar: cal).heading == "没有待办")
    }

    @Test func refreshesAtMidnightAndWhenTimedItemsComeDue() {
        let snapshot = WidgetSnapshot(entries: [
            EntrySnapshot(title: "组会", due: d(2026, 9, 14, 15), hasTime: true),
            EntrySnapshot(title: "早会", due: d(2026, 9, 14, 9), hasTime: true),
            EntrySnapshot(title: "没截止", due: d(2026, 9, 14, 16), hasTime: true, hasDue: false),
        ])
        #expect(snapshot.refreshDates(after: now, calendar: cal) == [d(2026, 9, 14, 15), d(2026, 9, 15)])
    }

    @Test func listSections() {
        #expect(ListSection.of(EntrySnapshot(title: "逾期", due: d(2026, 9, 12), urgency: .later), now: now, calendar: cal) == .attention)
        #expect(ListSection.of(EntrySnapshot(title: "下周", due: d(2026, 9, 21), urgency: .later), now: now, calendar: cal) == .later)
        #expect(ListSection.of(EntrySnapshot(title: "紧急", urgency: .urgent, hasDue: false), now: now, calendar: cal) == .urgent)
        #expect(ListSection.of(EntrySnapshot(title: "资料", urgency: .archive, hasDue: false), now: now, calendar: cal) == .archive)
    }
}

struct SharedContainerTests {
    func temporaryDirectory() throws -> URL {
        let url = FileManager.default.temporaryDirectory.appending(path: UUID().uuidString, directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: url, withIntermediateDirectories: true)
        return url
    }

    @Test func snapshotRoundTrip() throws {
        let directory = try temporaryDirectory()
        let snapshot = WidgetSnapshot(entries: [EntrySnapshot(title: "a", due: d(2026, 9, 15, 9, 30), hasTime: true)])
        try SharedContainer.writeSnapshot(snapshot, in: directory)
        #expect(SharedContainer.readSnapshot(in: directory) == snapshot)
    }

    @Test func inboxIsTakenOnceInOrder() throws {
        let directory = try temporaryDirectory()
        let first = InboxItem(text: "先记的", urgency: .later, createdAt: d(2026, 9, 14, 9))
        let second = InboxItem(text: "后记的", urgency: .urgent, due: d(2026, 9, 16, 15), hasTime: true, createdAt: d(2026, 9, 14, 11))
        try SharedContainer.addToInbox(second, in: directory)
        try SharedContainer.addToInbox(first, in: directory)
        let taken = SharedContainer.takeInbox(in: directory)
        #expect(taken == [first, second])
        #expect(taken[0].hasDue == false)
        #expect(taken[1].hasDue == true)
        #expect(SharedContainer.takeInbox(in: directory).isEmpty)
    }

    @Test func readsInboxFilesFromEarlierVersions() throws {
        let legacy = #"{"id":"6F1B3A52-3C1F-4B8B-9C11-0F4D0B6E9A01","text":"旧格式","due":800000000,"hasTime":false,"createdAt":800000000}"#
        let item = try JSONDecoder().decode(InboxItem.self, from: Data(legacy.utf8))
        #expect(item.urgency == .soon)
        #expect(item.hasDue)
    }
}
