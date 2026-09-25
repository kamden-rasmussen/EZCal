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

    // MARK: Join confirmation / idle deselect (issue #30)

    private func event(id: String, start: Date, minutes: Int, meetingURL: URL? = URL(string: "https://zoom.us/j/1")) -> CalEvent {
        CalEvent(id: id, eventId: id, sourceId: "s", calendarId: "c", accountId: "a", uid: id, title: id,
                 start: start, end: start.addingTimeInterval(Double(minutes) * 60), isAllDay: false, location: "",
                 notes: "", attendees: [], htmlLink: nil, meetingURL: meetingURL, colorHex: "#fff", sourceName: "",
                 ownerName: nil, isOverlay: false, canEdit: true, isBusyOnly: false, isRecurring: false,
                 zoomMeetingID: nil, isTentative: false, isDeclined: false)
    }

    func testCalEventIsInProgress() {
        let now = Date()
        let e = event(id: "e", start: now.addingTimeInterval(-600), minutes: 30)
        XCTAssertTrue(e.isInProgress(at: now))
        XCTAssertFalse(e.isInProgress(at: now.addingTimeInterval(-700)))   // before it starts
        XCTAssertFalse(e.isInProgress(at: now.addingTimeInterval(1800)))  // after it ends
    }

    func testJoinMeetingAsksToConfirmForFocusedPastEvent() {
        let store = CalendarStore()
        let past = event(id: "past", start: Date().addingTimeInterval(-3600), minutes: 30)
        store.calendars = [Source(id: "s", accountId: "a", calendarId: "c", name: "Cal", colorHex: "#fff", kind: .calendar)]
        store.eventsBySource["s"] = [past]
        store.rebuildDisplay()
        store.focusedEventID = past.id

        store.joinMeeting()
        XCTAssertEqual(store.joinRequest?.id, "past")
        XCTAssertNil(store.errorMessage)
    }

    func testJoinMeetingOpensDirectlyWhenFocusedEventIsInProgress() {
        // Checks the decision only (never `joinMeeting()` itself here) so this doesn't actually
        // shell out to NSWorkspace and launch a real app during the test run.
        let store = CalendarStore()
        let now = event(id: "now", start: Date().addingTimeInterval(-300), minutes: 30)
        store.calendars = [Source(id: "s", accountId: "a", calendarId: "c", name: "Cal", colorHex: "#fff", kind: .calendar)]
        store.eventsBySource["s"] = [now]
        store.rebuildDisplay()
        store.focusedEventID = now.id

        XCTAssertEqual(store.joinMeetingDecision(), .open(now.meetingURL!))
    }

    func testJoinMeetingOpensDirectlyWithinTenMinutesBeforeStart() {
        let store = CalendarStore()
        let soon = event(id: "soon", start: Date().addingTimeInterval(300), minutes: 30)
        store.calendars = [Source(id: "s", accountId: "a", calendarId: "c", name: "Cal", colorHex: "#fff", kind: .calendar)]
        store.eventsBySource["s"] = [soon]
        store.rebuildDisplay()
        store.focusedEventID = soon.id

        XCTAssertEqual(store.joinMeetingDecision(), .open(soon.meetingURL!))
    }

    func testJoinMeetingConfirmsWhenFocusedEventIsMoreThanTenMinutesAway() {
        let store = CalendarStore()
        let later = event(id: "later", start: Date().addingTimeInterval(1800), minutes: 30)
        store.calendars = [Source(id: "s", accountId: "a", calendarId: "c", name: "Cal", colorHex: "#fff", kind: .calendar)]
        store.eventsBySource["s"] = [later]
        store.rebuildDisplay()
        store.focusedEventID = later.id

        XCTAssertEqual(store.joinMeetingDecision(), .confirm(later))
    }

    func testJoinMeetingWithNoFocusAndNoUpcomingShowsError() {
        let store = CalendarStore()
        store.joinMeeting()
        XCTAssertNil(store.joinRequest)
        XCTAssertEqual(store.errorMessage, "No upcoming meeting with a video link.")
    }

    func testJoinMeetingOnFocusedEventWithNoLinkShowsError() {
        let store = CalendarStore()
        let noLink = event(id: "nolink", start: Date().addingTimeInterval(-300), minutes: 30, meetingURL: nil)
        store.calendars = [Source(id: "s", accountId: "a", calendarId: "c", name: "Cal", colorHex: "#fff", kind: .calendar)]
        store.eventsBySource["s"] = [noLink]
        store.rebuildDisplay()
        store.focusedEventID = noLink.id

        store.joinMeeting()
        XCTAssertNil(store.joinRequest)
        XCTAssertEqual(store.errorMessage, "That event has no video link.")
    }

    func testIdleExceeded() {
        let now = Date()
        XCTAssertFalse(CalendarStore.idleExceeded(lastInteraction: now.addingTimeInterval(-119), now: now))
        XCTAssertTrue(CalendarStore.idleExceeded(lastInteraction: now.addingTimeInterval(-120), now: now))
    }

    func testDeselectIfIdleClearsFocusAndMatchingDetailPanel() {
        let store = CalendarStore()
        let e = sampleEvent()
        store.focusedEventID = e.id
        store.sheet = .detail(e)
        store.lastInteractionAt = Date().addingTimeInterval(-121)

        store.deselectIfIdle()
        XCTAssertNil(store.focusedEventID)
        XCTAssertNil(store.sheet)
    }

    func testDeselectIfIdleLeavesUnrelatedSheetAlone() {
        let store = CalendarStore()
        store.focusedEventID = "e"
        store.sheet = .palette
        store.lastInteractionAt = Date().addingTimeInterval(-121)

        store.deselectIfIdle()
        XCTAssertNil(store.focusedEventID)
        XCTAssertEqual(store.sheet?.id, "palette")
    }

    func testDeselectIfIdleDoesNothingBeforeTimeout() {
        let store = CalendarStore()
        store.focusedEventID = "e"
        store.lastInteractionAt = Date().addingTimeInterval(-10)

        store.deselectIfIdle()
        XCTAssertEqual(store.focusedEventID, "e")
    }
}
