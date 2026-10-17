import XCTest
@testable import EZCal

/// Which calendars an existing event may be moved to, and how (issue #78).
final class EventMoveTests: XCTestCase {
    private func src(_ id: String, account: String, role: String = "owner", kind: Source.Kind = .calendar) -> Source {
        Source(id: id, accountId: account, calendarId: id, name: id, colorHex: "#000", kind: kind, accessRole: role)
    }
    private let g1 = "cal|a@x.com|one", g1b = "cal|a@x.com|two", g2 = "cal|b@x.com|three", ek1 = "ek|icloud|1", ek2 = "ek|exch|2"

    private func event(on sourceId: String, account: String = "a@x.com", recurring: Bool = false,
                       organizer: Bool = true, canEdit: Bool = true) -> CalEvent {
        var e = CalEvent(id: "e", eventId: "e", sourceId: sourceId, calendarId: sourceId, accountId: account, uid: "e",
                         title: "T", start: Date(), end: Date().addingTimeInterval(1800), isAllDay: false, location: "",
                         notes: "", attendees: [], htmlLink: nil, meetingURL: nil, colorHex: "#fff", sourceName: "",
                         ownerName: nil, isOverlay: false, canEdit: canEdit, isBusyOnly: false, isRecurring: recurring,
                         zoomMeetingID: nil, isTentative: false, isDeclined: false)
        e.isOrganizer = organizer
        return e
    }

    func testSameCalendarIsPlainEdit() {
        XCTAssertEqual(EventMove.plan(from: event(on: g1), to: src(g1, account: "a@x.com")), .none)
    }

    func testSameGoogleAccountUsesMove() {
        XCTAssertEqual(EventMove.plan(from: event(on: g1), to: src(g1b, account: "a@x.com")), .googleMove)
    }

    func testDifferentGoogleAccountRecreates() {
        XCTAssertEqual(EventMove.plan(from: event(on: g1), to: src(g2, account: "b@x.com")), .recreate)
    }

    func testEventKitToEventKit() {
        XCTAssertEqual(EventMove.plan(from: event(on: ek1, account: "ek:iCloud"), to: src(ek2, account: "ek:Exchange")), .eventKit)
    }

    func testCrossProviderRecreatesBothWays() {
        XCTAssertEqual(EventMove.plan(from: event(on: g1), to: src(ek1, account: "ek:iCloud")), .recreate)
        XCTAssertEqual(EventMove.plan(from: event(on: ek1, account: "ek:iCloud"), to: src(g1, account: "a@x.com")), .recreate)
    }

    func testRecurringEventsCannotMove() {
        XCTAssertEqual(EventMove.plan(from: event(on: g1, recurring: true), to: src(g1b, account: "a@x.com")), .unsupported)
        XCTAssertEqual(EventMove.plan(from: event(on: ek1, account: "ek:i", recurring: true), to: src(ek2, account: "ek:e")), .unsupported)
    }

    func testReadOnlyOrSubscribedDestinationsAreExcluded() {
        XCTAssertEqual(EventMove.plan(from: event(on: g1), to: src(g1b, account: "a@x.com", role: "reader")), .unsupported)
        XCTAssertEqual(EventMove.plan(from: event(on: g1), to: src("ics|x", account: "ics")), .unsupported)
        XCTAssertEqual(EventMove.plan(from: event(on: g1), to: src("person|a|b", account: "a@x.com", kind: .person)), .unsupported)
    }

    func testGuestEventsCannotMove() {
        XCTAssertEqual(EventMove.plan(from: event(on: g1, organizer: false), to: src(g1b, account: "a@x.com")), .unsupported)
        XCTAssertEqual(EventMove.plan(from: event(on: g1, organizer: false), to: src(ek1, account: "ek:i")), .unsupported)
    }

    func testDestinationsListIncludesCurrentAndMovableOnly() {
        let all = [src(g1, account: "a@x.com"), src(g1b, account: "a@x.com"), src(ek1, account: "ek:i"),
                   src("cal|a@x.com|ro", account: "a@x.com", role: "reader")]
        let ids = EventMove.destinations(for: event(on: g1), in: all).map(\.id)
        XCTAssertEqual(ids, [g1, g1b, ek1])
        XCTAssertEqual(EventMove.destinations(for: event(on: g1, recurring: true), in: all).map(\.id), [g1])
    }
}
