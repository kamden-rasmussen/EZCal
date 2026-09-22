import XCTest
import EventKit
@testable import EZCal

final class EventKitMappingTests: XCTestCase {
    private let src = Source(id: "ek|abc", accountId: "ek:iCloud", calendarId: "abc", name: "Home",
                             colorHex: "#FF0000", kind: .calendar, accessRole: "owner")

    func testTimedEventWithZoomLink() {
        let ev = EKEvent(eventStore: EKEventStore())
        ev.title = "Sync"
        ev.startDate = Date(timeIntervalSince1970: 1_800_000_000)
        ev.endDate = ev.startDate.addingTimeInterval(1800)
        ev.location = "https://acme.zoom.us/j/555"
        let e = EventKitService.map(ev, source: src)!
        XCTAssertEqual(e.title, "Sync")
        XCTAssertEqual(e.meetingProvider?.name, "Zoom")
        XCTAssertTrue(e.canEdit)
        XCTAssertTrue(e.isEventKit)
        XCTAssertFalse(e.isAllDay)
    }

    func testAllDayEndBecomesExclusive() {
        let cal = Calendar.current
        let day = cal.startOfDay(for: Date(timeIntervalSince1970: 1_800_000_000))
        let ev = EKEvent(eventStore: EKEventStore())
        ev.title = "Trip"
        ev.isAllDay = true
        ev.startDate = day
        ev.endDate = cal.date(byAdding: .day, value: 1, to: day)  // EventKit: inclusive last day (2 days)
        let e = EventKitService.map(ev, source: src)!
        XCTAssertEqual(cal.dateComponents([.day], from: e.start, to: e.end).day, 2)
    }

    func testReadOnlyCalendarCannotEdit() {
        var ro = src; ro.accessRole = "reader"
        let ev = EKEvent(eventStore: EKEventStore())
        ev.title = "Holiday"; ev.startDate = Date(); ev.endDate = Date().addingTimeInterval(3600)
        XCTAssertFalse(EventKitService.map(ev, source: ro)!.canEdit)
    }
}
