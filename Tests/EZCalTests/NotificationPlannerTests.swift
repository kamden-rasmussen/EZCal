import XCTest
@testable import EZCal

final class NotificationPlannerTests: XCTestCase {
    private func event(_ id: String, start: Date, minutes: Int = 30, isAllDay: Bool = false,
                        isDeclined: Bool = false, meetingURL: URL? = nil, location: String = "",
                        title: String? = nil) -> CalEvent {
        CalEvent(id: id, eventId: id, sourceId: "s", calendarId: "c", accountId: "a", uid: id,
                 title: title ?? id, start: start, end: start.addingTimeInterval(Double(minutes) * 60),
                 isAllDay: isAllDay, location: location, notes: "", attendees: [], htmlLink: nil,
                 meetingURL: meetingURL, colorHex: "#fff", sourceName: "", ownerName: nil, isOverlay: false,
                 canEdit: true, isBusyOnly: false, isRecurring: false, zoomMeetingID: nil, isTentative: false,
                 isDeclined: isDeclined)
    }

    func testEventFartherThanLeadTimeFiresAtLeadTime() {
        let now = Date()
        let start = now.addingTimeInterval(3600) // 1 hour out
        let plan = NotificationPlanner.plan(events: [event("a", start: start)], now: now, leadMinutes: 5, videoOnly: false)
        XCTAssertEqual(plan.count, 1)
        XCTAssertEqual(plan[0].fireDate.timeIntervalSince(start), -5 * 60, accuracy: 0.5)
    }

    func testEventStartingSoonerThanLeadTimeStillGetsAnImmediateReminder() {
        let now = Date()
        let start = now.addingTimeInterval(60) // starts in 1 minute, lead time is 5
        let plan = NotificationPlanner.plan(events: [event("a", start: start)], now: now, leadMinutes: 5, videoOnly: false)
        XCTAssertEqual(plan.count, 1)
        // Clamped to "now + a beat", not the (already past) ideal lead time, and still before the event starts.
        XCTAssertGreaterThan(plan[0].fireDate, now)
        XCTAssertLessThan(plan[0].fireDate, start)
    }

    func testEventAlreadyStartedIsNotScheduled() {
        let now = Date()
        let started = event("a", start: now.addingTimeInterval(-60), minutes: 30)
        let plan = NotificationPlanner.plan(events: [started], now: now, leadMinutes: 5, videoOnly: false)
        XCTAssertTrue(plan.isEmpty)
    }

    func testAllDayEventsAreExcluded() {
        let now = Date()
        let allDay = event("a", start: now.addingTimeInterval(3600), isAllDay: true)
        let plan = NotificationPlanner.plan(events: [allDay], now: now, leadMinutes: 5, videoOnly: false)
        XCTAssertTrue(plan.isEmpty)
    }

    func testDeclinedEventsAreExcluded() {
        let now = Date()
        let declined = event("a", start: now.addingTimeInterval(3600), isDeclined: true)
        let plan = NotificationPlanner.plan(events: [declined], now: now, leadMinutes: 5, videoOnly: false)
        XCTAssertTrue(plan.isEmpty)
    }

    func testVideoOnlyFilterKeepsOnlyEventsWithAMeetingLink() {
        let now = Date()
        let start = now.addingTimeInterval(3600)
        let noVideo = event("a", start: start)
        let withVideo = event("b", start: start, meetingURL: URL(string: "https://zoom.us/j/123"))
        let plan = NotificationPlanner.plan(events: [noVideo, withVideo], now: now, leadMinutes: 5, videoOnly: true)
        XCTAssertEqual(plan.map(\.eventID), ["b"])
    }

    func testJoinLinkCarriedThroughWhenPresent() {
        let now = Date()
        let start = now.addingTimeInterval(3600)
        let withVideo = event("a", start: start, meetingURL: URL(string: "https://zoom.us/j/123"))
        let plan = NotificationPlanner.plan(events: [withVideo], now: now, leadMinutes: 5, videoOnly: false)
        XCTAssertEqual(plan.first?.hasJoinLink, true)
        XCTAssertEqual(plan.first?.joinURLString, "https://zoom.us/j/123")

        let noVideo = event("b", start: start)
        let plan2 = NotificationPlanner.plan(events: [noVideo], now: now, leadMinutes: 5, videoOnly: false)
        XCTAssertEqual(plan2.first?.hasJoinLink, false)
        XCTAssertNil(plan2.first?.joinURLString)
    }

    func testIdentifierIsStableAcrossReplansButDiffersOnStartOrLeadChange() {
        let now = Date()
        let start = now.addingTimeInterval(3600)
        let e = event("a", start: start)

        let plan1 = NotificationPlanner.plan(events: [e], now: now, leadMinutes: 5, videoOnly: false)
        let plan2 = NotificationPlanner.plan(events: [e], now: now.addingTimeInterval(30), leadMinutes: 5, videoOnly: false)
        XCTAssertEqual(plan1.first?.id, plan2.first?.id, "replanning the same event/lead should keep the same id")

        let movedID = NotificationPlanner.identifier(for: event("a", start: start.addingTimeInterval(60)), leadMinutes: 5)
        XCTAssertNotEqual(plan1.first?.id, movedID, "a moved event should get a fresh id")

        let differentLeadID = NotificationPlanner.identifier(for: e, leadMinutes: 10)
        XCTAssertNotEqual(plan1.first?.id, differentLeadID, "a different lead time should get a fresh id")
    }

    func testUntitledEventGetsAPlaceholderTitle() {
        let now = Date()
        let e = event("a", start: now.addingTimeInterval(3600), title: "")
        let plan = NotificationPlanner.plan(events: [e], now: now, leadMinutes: 5, videoOnly: false)
        XCTAssertEqual(plan.first?.title, "Untitled event")
    }
}
