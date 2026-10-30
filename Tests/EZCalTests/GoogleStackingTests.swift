import XCTest
@testable import EZCal

/// Same meeting on several Google calendars should stack in the grid the way the iCloud copies do.
@MainActor
final class GoogleStackingTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func source(_ id: String) -> Source {
        Source(id: id, accountId: "acct", calendarId: id, name: id, colorHex: "#111111", kind: .calendar)
    }

    private func event(source: String, uid: String, start: Date) -> CalEvent {
        CalEvent(id: "\(source)|\(uid)", eventId: uid, sourceId: source, calendarId: source, accountId: "acct", uid: uid,
                 title: "Team sync", start: start, end: start.addingTimeInterval(1800), isAllDay: false,
                 location: "", notes: "", attendees: [], htmlLink: nil, meetingURL: nil, colorHex: "#fff",
                 sourceName: source, ownerName: nil, isOverlay: false, canEdit: true, isBusyOnly: false,
                 isRecurring: false, zoomMeetingID: nil, isTentative: false, isDeclined: false)
    }

    func testSameGoogleEventOnTwoCalendarsStacks() {
        let day = cal.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        let nine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
        let store = CalendarStore()
        store.calendars = [source("g1"), source("g2")]
        // Google gives the same event the same iCalUID on every calendar it's on.
        store.eventsBySource = ["g1": [event(source: "g1", uid: "shared@google.com", start: nine)],
                                "g2": [event(source: "g2", uid: "shared@google.com", start: nine)]]
        store.rebuildDisplay()
        let placed = EventLayout.place(store.displayEvents, day: day, cal: cal)
        XCTAssertEqual(placed.count, 1)
        guard case .stack(let events) = placed[0].item else { return XCTFail("expected a stack, got \(placed[0].item)") }
        XCTAssertEqual(Set(events.map(\.sourceId)), ["g1", "g2"])
    }

    func testOverlayOfOwnEventStillDropped() {
        let day = cal.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        let nine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
        let store = CalendarStore()
        store.calendars = [source("g1")]
        var theirs = event(source: "p1", uid: "shared@google.com", start: nine)
        theirs.isOverlay = true
        store.people = [Source(id: "p1", accountId: "acct", calendarId: "p1", name: "p1", colorHex: "#111111", kind: .person)]
        store.eventsBySource = ["g1": [event(source: "g1", uid: "shared@google.com", start: nine)], "p1": [theirs]]
        store.rebuildDisplay()
        XCTAssertEqual(store.displayEvents.map(\.sourceId), ["g1"])
    }

    func testSameCalendarRepeatStillDeduped() {
        let day = cal.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        let nine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
        let store = CalendarStore()
        store.calendars = [source("g1")]
        store.eventsBySource = ["g1": [event(source: "g1", uid: "x", start: nine), event(source: "g1", uid: "x", start: nine)]]
        store.rebuildDisplay()
        XCTAssertEqual(store.displayEvents.count, 1)
    }
}
