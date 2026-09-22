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

    // MARK: Drag to move / resize (issue #1)

    func testNudgeFocusedIsSafeWithNoFocusedEvent() {
        let store = CalendarStore()
        store.nudgeFocused(minutes: 15, resize: false)
        store.nudgeFocused(minutes: -15, resize: true)
        XCTAssertNil(store.dragPreview)
    }

    func testCancelDragClearsPreviewAndSetsFlag() {
        let store = CalendarStore()
        store.dragPreview = EventDragPreview(kind: .move, event: sampleEvent(), day: Date(), start: Date(), end: Date())
        store.cancelDrag()
        XCTAssertNil(store.dragPreview)
        XCTAssertTrue(store.dragCancelled)
    }

    private func sampleEvent() -> CalEvent {
        CalEvent(id: "e", eventId: "e", sourceId: "s", calendarId: "c", accountId: "a", uid: "e", title: "Sample",
                 start: Date(), end: Date().addingTimeInterval(1800), isAllDay: false, location: "", notes: "",
                 attendees: [], htmlLink: nil, meetingURL: nil, colorHex: "#fff", sourceName: "",
                 ownerName: nil, isOverlay: false, canEdit: true, isBusyOnly: false, isRecurring: false,
                 zoomMeetingID: nil, isTentative: false, isDeclined: false)
    }
}
