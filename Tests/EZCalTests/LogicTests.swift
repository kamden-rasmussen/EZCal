import XCTest
@testable import EZCal

final class LogicTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func event(_ id: String, _ start: Date, minutes: Int, source: String = "s", title: String? = nil,
                        isOverlay: Bool = false, isBusyOnly: Bool = false) -> CalEvent {
        CalEvent(id: id, eventId: id, sourceId: source, calendarId: source, accountId: "a", uid: id, title: title ?? id,
                 start: start, end: start.addingTimeInterval(Double(minutes) * 60), isAllDay: false,
                 location: "", notes: "", attendees: [], htmlLink: nil, meetingURL: nil, colorHex: "#fff",
                 sourceName: source, ownerName: nil, isOverlay: isOverlay, canEdit: true, isBusyOnly: isBusyOnly,
                 isRecurring: false, zoomMeetingID: nil, isTentative: false, isDeclined: false)
    }

    func testOverlappingEventsGetSeparateColumns() {
        let day = cal.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        let nine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
        let placed = EventLayout.place([
            event("a", nine, minutes: 60),
            event("b", nine.addingTimeInterval(1800), minutes: 60),   // overlaps a
            event("c", nine.addingTimeInterval(4 * 3600), minutes: 30), // alone
        ], day: day, cal: cal)
        let byId = Dictionary(uniqueKeysWithValues: placed.map { ($0.id, $0) })
        XCTAssertEqual(byId["a"]!.columns, 2)
        XCTAssertEqual(byId["b"]!.columns, 2)
        XCTAssertNotEqual(byId["a"]!.column, byId["b"]!.column)
        XCTAssertEqual(byId["c"]!.columns, 1)
    }

    func testSameMeetingOnDifferentCalendarsStacks() {
        let day = cal.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        let nine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
        let placed = EventLayout.place([
            event("g", nine, minutes: 30, source: "google", title: "Team standup"),
            event("i", nine.addingTimeInterval(60), minutes: 30, source: "icloud", title: "  Team Standup "),
            event("f", nine.addingTimeInterval(-120), minutes: 30, source: "family", title: "team standup"),
        ], day: day, cal: cal)
        XCTAssertEqual(placed.count, 1)
        guard case .stack(let events) = placed[0].item else { return XCTFail("expected a stack") }
        XCTAssertEqual(Set(events.map(\.id)), Set(["g", "i", "f"]))
        XCTAssertEqual(placed[0].columns, 1)   // stacked into one block, not packed into side-by-side columns
    }

    func testSameCalendarDuplicateDoesNotStack() {
        // Two distinct events that happen to share a title on the SAME calendar aren't a cross-calendar duplicate.
        let day = cal.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        let nine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
        let placed = EventLayout.place([
            event("a", nine, minutes: 30, source: "google", title: "Sync"),
            event("b", nine, minutes: 30, source: "google", title: "Sync"),
        ], day: day, cal: cal)
        XCTAssertEqual(placed.count, 2)
        for p in placed { if case .single = p.item {} else { XCTFail("expected singles") } }
    }

    func testOverlayAndBusyEventsNeverStack() {
        let day = cal.date(from: DateComponents(year: 2026, month: 3, day: 2))!
        let nine = cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
        let placed = EventLayout.place([
            event("mine", nine, minutes: 30, source: "google", title: "Sync"),
            event("theirs", nine, minutes: 30, source: "coworker", title: "Sync", isOverlay: true),
        ], day: day, cal: cal)
        XCTAssertEqual(placed.count, 2)
        for p in placed { if case .single = p.item {} else { XCTFail("expected singles") } }
    }

    func testMeetingLinkDetection() {
        let zoom = MeetingLink.find(in: ["", "Join: https://acme.zoom.us/j/123456789?pwd=abc&amp;x=1."])
        XCTAssertEqual(zoom?.absoluteString, "https://acme.zoom.us/j/123456789?pwd=abc&x=1")
        XCTAssertEqual(MeetingProvider(url: zoom!).name, "Zoom")
        XCTAssertEqual(MeetingLink.find(in: ["<a href=\"https://meet.google.com/abc-defg-hij\">x</a>"])?.absoluteString,
                       "https://meet.google.com/abc-defg-hij")
        XCTAssertNil(MeetingLink.find(in: ["lunch at the cafe"]))
    }

    func testDateParsing() {
        XCTAssertNotNil(RFC3339.parse("2026-03-02T09:00:00-08:00"))
        XCTAssertNotNil(RFC3339.parse("2026-03-02T17:00:00.000Z"))
        XCTAssertEqual(RFC3339.string(RFC3339.parse("2026-03-02T09:00:00-08:00")!), "2026-03-02T17:00:00Z")
        XCTAssertNotNil(RFC3339.parseDay("2026-03-02"))
    }

    func testEventMapping() throws {
        let json = """
        {"id":"e1","summary":"Standup","iCalUID":"u1","location":"https://x.zoom.us/j/9",
         "start":{"dateTime":"2026-03-02T09:00:00-08:00"},"end":{"dateTime":"2026-03-02T09:30:00-08:00"},
         "attendees":[{"email":"me@x.com","self":true,"responseStatus":"accepted"},
                      {"email":"bob@x.com","responseStatus":"declined"}],
         "extendedProperties":{"private":{"zoomMeetingId":"9"}}}
        """
        let g = try JSONDecoder().decode(GEvent.self, from: Data(json.utf8))
        let src = Source(id: "cal|a|c", accountId: "a", calendarId: "c", name: "Me", colorHex: "#111111", kind: .calendar, accessRole: "owner")
        let e = EventMapper.map(g, source: src)!
        XCTAssertEqual(e.title, "Standup")
        XCTAssertEqual(e.meetingProvider?.name, "Zoom")
        XCTAssertEqual(e.zoomMeetingID, "9")
        XCTAssertTrue(e.canEdit)
        XCTAssertEqual(e.selfAttendee?.response, "accepted")

        // Bob declined: he shouldn't see it on his overlay.
        let bob = Source(id: "person|a|bob@x.com", accountId: "a", calendarId: "bob@x.com", name: "Bob", colorHex: "#222", kind: .person)
        XCTAssertNil(EventMapper.map(g, source: bob, ownerName: "Bob", ownerEmail: "bob@x.com"))
    }

    func testAllDayEndIsExclusive() throws {
        let json = #"{"id":"e2","summary":"Offsite","start":{"date":"2026-03-02"},"end":{"date":"2026-03-04"}}"#
        let g = try JSONDecoder().decode(GEvent.self, from: Data(json.utf8))
        let src = Source(id: "s", accountId: "a", calendarId: "c", name: "x", colorHex: "#111", kind: .calendar)
        let e = EventMapper.map(g, source: src)!
        XCTAssertTrue(e.isAllDay)
        XCTAssertEqual(Calendar.current.dateComponents([.day], from: e.start, to: e.end).day, 2)
    }
}
