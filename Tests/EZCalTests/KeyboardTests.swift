import XCTest
@testable import EZCal

@MainActor
final class KeyboardTests: XCTestCase {
    func testNaturalLanguageDates() {
        XCTAssertNotNil(CalendarStore.parseDate("tomorrow"))
        XCTAssertNotNil(CalendarStore.parseDate("next friday"))
        XCTAssertNil(CalendarStore.parseDate("zzzz"))
    }

    func testPaletteDefaultsAndFiltering() {
        let store = CalendarStore()
        let defaults = store.paletteItems(for: "").map(\.id)
        XCTAssertTrue(defaults.contains("new"))
        XCTAssertTrue(defaults.contains("week"))

        let filtered = store.paletteItems(for: "month").map(\.id)
        XCTAssertTrue(filtered.contains("month"))
        XCTAssertFalse(filtered.contains("today"))

        // "go to <date>" yields a jump-to-date command first.
        XCTAssertEqual(store.paletteItems(for: "go to tomorrow").first?.id, "date")
    }

    func testEmptyStoreFocusMovesAreSafe() {
        let store = CalendarStore()
        store.moveFocus(1); store.moveFocus(-1); store.moveFocusDay(1)
        XCTAssertNil(store.focusedEventID)
    }
}
