import XCTest
@testable import EZCal

final class GuestPermissionTests: XCTestCase {
    private let mine = Source(id: "cal|a@x.com|a@x.com", accountId: "a@x.com", calendarId: "a@x.com", name: "Me",
                              colorHex: "#FF0000", kind: .calendar, accessRole: "owner")

    private func event(_ extra: String) throws -> CalEvent {
        let json = """
        {"id":"e1","status":"confirmed","summary":"Sync","iCalUID":"e1@google.com",
         "start":{"dateTime":"2030-01-01T10:00:00Z"},"end":{"dateTime":"2030-01-01T11:00:00Z"}\(extra)}
        """
        let g = try JSONDecoder().decode(GEvent.self, from: Data(json.utf8))
        return try XCTUnwrap(EventMapper.map(g, source: mine))
    }

    func testOwnEventIsFullyEditable() throws {
        let e = try event(",\"organizer\":{\"email\":\"a@x.com\",\"self\":true}")
        XCTAssertTrue(e.isOrganizer)
        XCTAssertTrue(e.canModify)
        XCTAssertFalse(e.isGuestInviteOnly)
    }

    func testEventWithoutOrganizerCountsAsOwn() throws {
        XCTAssertTrue(try event("").canModify)
    }

    func testGuestOnOthersEventMayOnlyInviteByDefault() throws {
        let e = try event(",\"organizer\":{\"email\":\"b@x.com\"}")
        XCTAssertFalse(e.isOrganizer)
        XCTAssertFalse(e.canModify)
        XCTAssertTrue(e.isGuestInviteOnly)
    }

    func testOrganizerCanDisallowInvitingOthers() throws {
        let e = try event(",\"organizer\":{\"email\":\"b@x.com\"},\"guestsCanInviteOthers\":false")
        XCTAssertFalse(e.isGuestInviteOnly)
        XCTAssertFalse(e.canModify)
    }

    func testGuestsCanModifyGrantsFullEditing() throws {
        let e = try event(",\"organizer\":{\"email\":\"b@x.com\"},\"guestsCanModify\":true")
        XCTAssertTrue(e.canModify)
        XCTAssertFalse(e.isGuestInviteOnly)
    }
}

extension GuestPermissionTests {
    func testGuestPatchBodyCarriesExistingAndNewGuests() {
        let body = CalendarStore.attendeeBody([
            Attendee(email: "boss@x.com", name: "Boss", response: "accepted", isOrganizer: true),
            Attendee(email: "me@x.com", response: "tentative", isSelf: true),
            Attendee(email: "new@x.com"),
        ], existing: true)
        XCTAssertEqual(body.map { $0["email"] as? String }, ["boss@x.com", "me@x.com", "new@x.com"])
        XCTAssertEqual(body.map { $0["responseStatus"] as? String }, ["accepted", "tentative", "needsAction"])
        XCTAssertEqual(body[0]["displayName"] as? String, "Boss")
    }

    func testNewEventBodyOmitsResponseStatus() {
        let body = CalendarStore.attendeeBody([Attendee(email: "a@x.com")], existing: false)
        XCTAssertNil(body[0]["responseStatus"])
    }
}
