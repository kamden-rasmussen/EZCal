import XCTest
@testable import EZCal

/// Multi-window support (⌘⇧N) gives each window its own `CalendarStore` instance, so per-window
/// navigation state (anchor / mode / focus / sheet / sidebar visibility) must not leak between them.
@MainActor
final class WindowStateTests: XCTestCase {
    func testNavigationStateIsIsolatedBetweenStores() {
        let a = CalendarStore()
        let b = CalendarStore()

        a.mode = .day
        b.mode = .month
        a.anchor = Date(timeIntervalSince1970: 0)
        b.anchor = Date(timeIntervalSince1970: 1_000_000)
        a.focusedEventID = "abc"
        a.columnVisibility = .detailOnly

        XCTAssertNotEqual(a.mode, b.mode)
        XCTAssertNotEqual(a.anchor, b.anchor)
        XCTAssertEqual(a.focusedEventID, "abc")
        XCTAssertNil(b.focusedEventID)
        XCTAssertNotEqual(a.columnVisibility, b.columnVisibility)
    }

    func testSheetStateIsIsolatedBetweenStores() {
        let a = CalendarStore()
        let b = CalendarStore()

        a.sheet = .shortcuts
        XCTAssertNotNil(a.sheet)
        XCTAssertNil(b.sheet)
    }
}
