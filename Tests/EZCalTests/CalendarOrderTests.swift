import XCTest
@testable import EZCal

/// Drag-to-reorder ranking for sidebar calendars (`CalendarStore.ordered`/`moveCalendar`) — see `SidebarView`'s
/// `ReorderableSourceList`.
@MainActor
final class CalendarOrderTests: XCTestCase {
    // `CalendarStore` persists `sourceOrder` to UserDefaults.standard (the real defaults, same as the
    // app) — see TasksStoreTests for the same pattern with `hiddenTaskLists`.
    override func setUp() { UserDefaults.standard.removeObject(forKey: "sourceOrder") }
    override func tearDown() { UserDefaults.standard.removeObject(forKey: "sourceOrder") }

    private func source(_ id: String) -> Source {
        Source(id: id, accountId: "a", calendarId: id, name: id, colorHex: "#111111", kind: .calendar)
    }

    func testOrderedLeavesUntouchedListAsIs() {
        let store = CalendarStore()
        let items = [source("a"), source("b"), source("c")]
        XCTAssertEqual(store.ordered(items).map(\.id), ["a", "b", "c"])
    }

    func testMoveCalendarReordersWithinGroup() {
        let store = CalendarStore()
        let items = [source("a"), source("b"), source("c")]

        // Drag "c" (index 2) to the top.
        store.moveCalendar("c", toIndex: 0, within: items)
        XCTAssertEqual(store.ordered(items).map(\.id), ["c", "a", "b"])
    }

    func testMoveCalendarDownward() {
        let store = CalendarStore()
        let items = [source("a"), source("b"), source("c"), source("d")]

        // Drag "a" (index 0) down to index 2.
        store.moveCalendar("a", toIndex: 2, within: items)
        XCTAssertEqual(store.ordered(items).map(\.id), ["b", "c", "a", "d"])
    }

    func testUnrankedNewCalendarSortsAfterRankedOnes() {
        let store = CalendarStore()
        let items = [source("a"), source("b")]
        store.moveCalendar("b", toIndex: 0, within: items)   // now ranked: b, a

        // A calendar that showed up later (never dragged) should trail the ranked ones, not jump ahead.
        let withNewOne = [source("a"), source("b"), source("new")]
        XCTAssertEqual(store.ordered(withNewOne).map(\.id), ["b", "a", "new"])
    }

    func testReorderingOneGroupDoesNotDisturbAnother() {
        let store = CalendarStore()
        let groupOne = [source("a1"), source("a2")]
        let groupTwo = [source("b1"), source("b2")]

        store.moveCalendar("a2", toIndex: 0, within: groupOne)
        XCTAssertEqual(store.ordered(groupOne).map(\.id), ["a2", "a1"])
        // groupTwo was never dragged, so its members (interleaved in the same flat sourceOrder as
        // groupOne's) should still come back in their original relative order.
        XCTAssertEqual(store.ordered(groupTwo).map(\.id), ["b1", "b2"])
    }

    func testMoveToSameIndexIsNoOp() {
        let store = CalendarStore()
        let items = [source("a"), source("b")]
        store.moveCalendar("a", toIndex: 0, within: items)
        XCTAssertEqual(store.ordered(items).map(\.id), ["a", "b"])
    }
}
