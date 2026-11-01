import XCTest
@testable import EZCal

final class AttendeeRSVPTests: XCTestCase {
    private let list = [
        Attendee(email: "me@x.com", name: "Me", response: "needsAction", isSelf: true),
        Attendee(email: "a@x.com", name: "A", response: "accepted", isOrganizer: true),
        Attendee(email: "b@x.com", name: "B", response: "declined")]

    func testRSVPChangesOnlySelf() {
        let out = CalendarStore.attendeesSettingSelfResponse(list, to: "tentative")
        XCTAssertEqual(out.map(\.response), ["tentative", "accepted", "declined"])
        XCTAssertEqual(out.map(\.email), list.map(\.email))
    }

    func testDemoDirectoryMatchesNameOrEmailCaseInsensitively() {
        XCTAssertEqual(CalendarStore.demoDirectory(matching: "ALEX").map(\.email), ["alex@example.com"])
        XCTAssertEqual(CalendarStore.demoDirectory(matching: "jordan@").map(\.name), ["Jordan Kim"])
        XCTAssertTrue(CalendarStore.demoDirectory(matching: "a").isEmpty, "needs two characters")
        XCTAssertTrue(CalendarStore.demoDirectory(matching: "zzzz").isEmpty)
    }
}
