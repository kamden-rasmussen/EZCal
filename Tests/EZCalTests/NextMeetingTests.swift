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

    // MARK: - What J joins (#212)

    private func candidates(_ events: [CalEvent]) -> [String] { CalEvent.joinCandidates(in: events, now: now).map(\.id) }

    func testJoinSkipsAnUnfinishedEventWithoutAVideoLink() {
        // A call-less block that started earlier must not shadow the video meeting that is under way.
        XCTAssertEqual(candidates([event("focus", startsIn: -60, minutes: 120, video: false), event("call", startsIn: -5)]), ["call"])
    }

    func testJoinSkipsAllDayEvents() {
        var allDay = event("trip", startsIn: -600, minutes: 1440)
        allDay.isAllDay = true
        XCTAssertEqual(candidates([allDay, event("call", startsIn: -5)]), ["call"])
    }

    func testJoinHasNothingWhenNoEventHasAVideoLink() {
        XCTAssertEqual(candidates([event("a", startsIn: -5, video: false), event("b", startsIn: 20, video: false)]), [])
    }

    func testJoinAsksWhenTwoVideoMeetingsStartTogether() {
        var other = event("b", startsIn: -5)
        other.meetingURL = URL(string: "https://meet.google.com/abc")
        XCTAssertEqual(Set(candidates([event("a", startsIn: -5), other])), ["a", "b"])
    }

    func testJoinTreatsCopiesOnSeveralCalendarsAsOneMeeting() {
        // Same link on two calendars: not a real choice.
        XCTAssertEqual(candidates([event("a", startsIn: -5), event("a2", startsIn: -5)]), ["a"])
    }

    func testJoinDoesNotAskWhenMeetingsStartAtDifferentTimes() {
        var later = event("b", startsIn: 20)
        later.meetingURL = URL(string: "https://meet.google.com/abc")
        XCTAssertEqual(candidates([event("a", startsIn: -5), later]), ["a"])
    }
}
