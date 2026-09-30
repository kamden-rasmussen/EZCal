import XCTest
@testable import EZCal

final class NextMeetingTests: XCTestCase {
    private let now = Date()

    private func event(_ id: String, startsIn m: Double, minutes: Double = 30, video: Bool = true) -> CalEvent {
        let start = now.addingTimeInterval(m * 60)
        return CalEvent(id: id, eventId: id, sourceId: "s", calendarId: "c", accountId: "a", uid: id, title: id,
                        start: start, end: start.addingTimeInterval(minutes * 60), isAllDay: false, location: "",
                        notes: "", attendees: [], htmlLink: nil,
                        meetingURL: video ? URL(string: "https://zoom.us/j/1") : nil, colorHex: "#fff", sourceName: "",
                        ownerName: nil, isOverlay: false, canEdit: true, isBusyOnly: false, isRecurring: false,
                        zoomMeetingID: nil, isTentative: false, isDeclined: false)
    }

    private func pick(_ events: [CalEvent]) -> String? { CalEvent.nextMeeting(in: events, now: now)?.id }

    func testCurrentMeetingStaysWhenNextIsFarOff() {
        XCTAssertEqual(pick([event("a", startsIn: -10), event("b", startsIn: 25)]), "a")
    }

    func testNextVideoMeetingTakesOverWithinTenMinutes() {
        XCTAssertEqual(pick([event("a", startsIn: -10), event("b", startsIn: 9)]), "b")
        XCTAssertEqual(pick([event("a", startsIn: -10), event("b", startsIn: 10)]), "b")
        XCTAssertEqual(pick([event("a", startsIn: -10), event("b", startsIn: 11)]), "a")
    }

    func testInPersonEventDoesNotDisplaceCurrentMeeting() {
        XCTAssertEqual(pick([event("a", startsIn: -10), event("b", startsIn: 5, video: false)]), "a")
    }

    func testWithNothingInProgressPicksFirstUpcoming() {
        XCTAssertEqual(pick([event("a", startsIn: 30, video: false), event("b", startsIn: 5)]), "a")
    }

    func testNilWhenEverythingHasEnded() {
        XCTAssertNil(pick([event("a", startsIn: -60, minutes: 30)]))
    }
}
