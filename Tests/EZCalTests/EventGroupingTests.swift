import XCTest
@testable import EZCal

/// `EventGrouping` / `EventLayout.place` now live in Core (shared with iOS): same meeting on several
/// calendars folds into one stack; a different overlapping event stays separate.
final class EventGroupingTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)
    private var day: Date { cal.date(from: DateComponents(year: 2026, month: 3, day: 2))! }
    private var nine: Date { cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)! }

    private func event(_ id: String, title: String, source: String, minutes: Int = 60, offset: Double = 0) -> CalEvent {
        let s = nine.addingTimeInterval(offset)
        return CalEvent(id: id, eventId: id, sourceId: source, calendarId: source, accountId: "a", uid: id, title: title,
                 start: s, end: s.addingTimeInterval(Double(minutes) * 60), isAllDay: false,
                 location: "", notes: "", attendees: [], htmlLink: nil, meetingURL: nil, colorHex: "#fff",
                 sourceName: source, ownerName: nil, isOverlay: false, canEdit: true, isBusyOnly: false,
                 isRecurring: false, zoomMeetingID: nil, isTentative: false, isDeclined: false)
    }

    func testSameMeetingOnThreeCalendarsFoldsIntoOneStack() {
        let items = EventGrouping.group([event("a", title: "Sync", source: "s1"),
                                         event("b", title: " sync ", source: "s2", offset: 120),
                                         event("c", title: "Sync", source: "s3")])
        XCTAssertEqual(items.count, 1)
        if case .stack(let es) = items[0] { XCTAssertEqual(es.count, 3) } else { XCTFail("expected stack") }
    }

    func testSameCalendarDuplicatesAndDifferentTitlesDoNotFold() {
        XCTAssertEqual(EventGrouping.group([event("a", title: "Sync", source: "s1"), event("b", title: "Sync", source: "s1")]).count, 2)
        XCTAssertEqual(EventGrouping.group([event("a", title: "Sync", source: "s1"), event("b", title: "Other", source: "s2")]).count, 2)
    }

    func testStackPlusGenuinelyOverlappingEventSplitsIntoTwoSideSlots() {
        let placed = EventLayout.place([event("a", title: "Sync", source: "s1"),
                                        event("b", title: "Sync", source: "s2"),
                                        event("c", title: "Review", source: "s1", offset: 15 * 60)], day: day, cal: cal)
        XCTAssertEqual(placed.count, 2)
        XCTAssertEqual(Set(placed.map(\.sideSlot)).count, 2)
        XCTAssertTrue(placed.allSatisfy { $0.sideSlots == 2 })
    }

    func testStackAloneUsesOneSlot() {
        let placed = EventLayout.place([event("a", title: "Sync", source: "s1"), event("b", title: "Sync", source: "s2")], day: day, cal: cal)
        XCTAssertEqual(placed.count, 1)
        XCTAssertEqual(placed[0].sideSlots, 1)
    }
}
