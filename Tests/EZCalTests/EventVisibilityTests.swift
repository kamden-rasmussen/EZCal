import XCTest
@testable import EZCal

final class EventVisibilityTests: XCTestCase {
    private let mine = Source(id: "cal|a@x.com|a@x.com", accountId: "a@x.com", calendarId: "a@x.com", name: "Me",
                              colorHex: "#FF0000", kind: .calendar, accessRole: "owner")
    private let coworker = Source(id: "person|a@x.com|b@x.com", accountId: "a@x.com", calendarId: "b@x.com", name: "Bob Lee",
                                  colorHex: "#00FF00", kind: .person)

    private func gevent(_ json: String) throws -> GEvent {
        try JSONDecoder().decode(GEvent.self, from: Data(json.utf8))
    }

    private func json(visibility: String?) -> String {
        let vis = visibility.map { ",\"visibility\":\"\($0)\"" } ?? ""
        return """
        {"id":"e1","status":"confirmed","summary":"Therapy","description":"secret","location":"Room 5",
         "iCalUID":"e1@google.com","htmlLink":"https://example.com/e1",
         "start":{"dateTime":"2030-01-01T10:00:00Z"},"end":{"dateTime":"2030-01-01T11:00:00Z"},
         "attendees":[{"email":"c@x.com"}]\(vis)}
        """
    }

    func testAPIValueParsing() {
        XCTAssertEqual(EventVisibility(apiValue: nil), .default)
        XCTAssertEqual(EventVisibility(apiValue: "default"), .default)
        XCTAssertEqual(EventVisibility(apiValue: "public"), .public)
        XCTAssertEqual(EventVisibility(apiValue: "private"), .private)
        // Unknown/legacy values fail closed.
        XCTAssertEqual(EventVisibility(apiValue: "confidential"), .private)
    }

    func testCodableRoundTrip() throws {
        for v in EventVisibility.allCases {
            let data = try JSONEncoder().encode([v])
            XCTAssertEqual(try JSONDecoder().decode([EventVisibility].self, from: data), [v])
        }
        XCTAssertEqual(EventVisibility.private.rawValue, "private")
    }

    func testOwnEventKeepsDetailsAndVisibility() throws {
        let e = try XCTUnwrap(EventMapper.map(try gevent(json(visibility: "private")), source: mine))
        XCTAssertEqual(e.visibility, .private)
        XCTAssertTrue(e.isPrivate)
        XCTAssertFalse(e.isBusyOnly)
        XCTAssertEqual(e.title, "Therapy")
        XCTAssertEqual(e.location, "Room 5")
        XCTAssertEqual(e.notes, "secret")
        XCTAssertTrue(e.canEdit)
    }

    func testMissingVisibilityIsDefault() throws {
        let e = try XCTUnwrap(EventMapper.map(try gevent(json(visibility: nil)), source: mine))
        XCTAssertEqual(e.visibility, .default)
        XCTAssertFalse(e.isPrivate)
    }

    func testCoworkerPrivateEventBecomesBusyOnly() throws {
        let e = try XCTUnwrap(EventMapper.map(try gevent(json(visibility: "private")), source: coworker, ownerName: "Bob"))
        XCTAssertTrue(e.isBusyOnly)
        XCTAssertTrue(e.isOverlay)
        XCTAssertFalse(e.canEdit)
        XCTAssertEqual(e.title, "Busy")
        XCTAssertEqual(e.location, "")
        XCTAssertEqual(e.notes, "")
        XCTAssertTrue(e.attendees.isEmpty)
        XCTAssertNil(e.htmlLink)
        XCTAssertNil(e.meetingURL)
        XCTAssertEqual(e.eventId, "e1")
        XCTAssertEqual(e.start, RFC3339.parse("2030-01-01T10:00:00Z"))
    }

    func testCoworkerPublicEventStillShowsDetails() throws {
        let e = try XCTUnwrap(EventMapper.map(try gevent(json(visibility: "public")), source: coworker, ownerName: "Bob"))
        XCTAssertFalse(e.isBusyOnly)
        XCTAssertEqual(e.title, "Therapy")
    }

    func testDraftDefaultsToDefaultVisibility() {
        let d = EventDraft(start: Date(), end: Date().addingTimeInterval(3600), sourceId: mine.id)
        XCTAssertEqual(d.visibility, .default)
    }
}
