import Foundation
import Testing
@testable import WanderlyCore

struct WidgetSnapshotTests {
    let now = d(2026, 9, 14, 10)

    @Test func keepsActiveEntriesSorted() {
        let snapshot = WidgetSnapshot(entries: [
            EntrySnapshot(title: "b", due: d(2026, 9, 16)),
            EntrySnapshot(title: "做完了", due: d(2026, 9, 13), state: .done),
            EntrySnapshot(title: "a", due: d(2026, 9, 12), state: .open),
        ])
        #expect(snapshot.items.map(\.title) == ["a", "b"])
        #expect(snapshot.roughCount == 1)
    }

    @Test func focusPrefersOverdueAndToday() {
        let snapshot = WidgetSnapshot(entries: [
            EntrySnapshot(title: "逾期", due: d(2026, 9, 12), state: .open),
            EntrySnapshot(title: "今天", due: d(2026, 9, 14, 15), hasTime: true, state: .open),
            EntrySnapshot(title: "以后", due: d(2026, 9, 30), state: .open),
        ])
        let focus = snapshot.focus(at: now, limit: 3, calendar: cal)
        #expect(focus.heading == "今天")
        #expect(focus.urgentCount == 2)
        #expect(focus.items.map(\.title) == ["逾期", "今天"])
    }

    @Test func focusFallsBackToUpcoming() {
        let snapshot = WidgetSnapshot(entries: [EntrySnapshot(title: "以后", due: d(2026, 9, 30), state: .open)])
        let focus = snapshot.focus(at: now, limit: 3, calendar: cal)
        #expect(focus.heading == "接下来")
        #expect(focus.urgentCount == 0)
        #expect(focus.items.count == 1)
        #expect(WidgetSnapshot.empty.focus(at: now, limit: 3, calendar: cal).heading == "没有待办")
    }

    @Test func refreshesAtMidnightAndWhenTimedItemsComeDue() {
        let snapshot = WidgetSnapshot(entries: [
            EntrySnapshot(title: "组会", due: d(2026, 9, 14, 15), hasTime: true),
            EntrySnapshot(title: "早会", due: d(2026, 9, 14, 9), hasTime: true),
        ])
        #expect(snapshot.refreshDates(after: now, calendar: cal) == [d(2026, 9, 14, 15), d(2026, 9, 15)])
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
        let first = InboxItem(text: "先记的", due: d(2026, 9, 15), hasTime: false, createdAt: d(2026, 9, 14, 9))
        let second = InboxItem(text: "后记的", due: d(2026, 9, 16, 15), hasTime: true, createdAt: d(2026, 9, 14, 11))
        try SharedContainer.addToInbox(second, in: directory)
        try SharedContainer.addToInbox(first, in: directory)
        #expect(SharedContainer.takeInbox(in: directory) == [first, second])
        #expect(SharedContainer.takeInbox(in: directory).isEmpty)
    }
}
