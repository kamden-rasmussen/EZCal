import XCTest
@testable import EZCal

@MainActor
final class DuplicateEventTests: XCTestCase {
    private let mine = Source(id: "cal|a@x.com|a@x.com", accountId: "a@x.com", calendarId: "a@x.com", name: "Me",
                              colorHex: "#FF0000", kind: .calendar, accessRole: "owner")
    private let work = Source(id: "cal|a@x.com|w@x.com", accountId: "a@x.com", calendarId: "w@x.com", name: "Work",
                              colorHex: "#0000FF", kind: .calendar, accessRole: "writer")

    private func event(allDay: Bool = false, visibility: String? = "private") throws -> CalEvent {
        let when = allDay
            ? #""start":{"date":"2030-01-01"},"end":{"date":"2030-01-03"}"#
            : #""start":{"dateTime":"2030-01-01T10:00:00Z"},"end":{"dateTime":"2030-01-01T11:00:00Z"}"#
        let vis = visibility.map { #","visibility":"\#($0)""# } ?? ""
        let json = """
        {"id":"e1","status":"confirmed","summary":"Lunch","description":"notes","location":"Cafe",
         "iCalUID":"e1@google.com",\(when),
         "attendees":[{"email":"a@x.com","self":true},{"email":"c@x.com"},{"email":"room@x.com","resource":true}]\(vis)}
        """
        let g = try JSONDecoder().decode(GEvent.self, from: Data(json.utf8))
        return try XCTUnwrap(EventMapper.map(g, source: mine, ownerName: nil))
    }

    private func draft(_ store: CalendarStore) throws -> EventDraft {
        guard case .editor(let d)? = store.sheet else { throw XCTSkip("no editor sheet") }
        return d
    }

    func testDuplicateOpensNewDraftOnChosenCalendar() throws {
        let store = CalendarStore()
        store.duplicateDraft(try event(), to: work)
        let d = try draft(store)
        XCTAssertNil(d.existing)
        XCTAssertEqual(d.sourceId, work.id)
        XCTAssertEqual(d.title, "Lunch")
        XCTAssertEqual(d.location, "Cafe")
        XCTAssertEqual(d.notes, "notes")
        XCTAssertEqual(d.visibility, .private)
        XCTAssertEqual(d.recurrence, .none)
        XCTAssertFalse(d.isAllDay)
    }

    func testDuplicateDropsSelfAndResourceAttendees() throws {
        let store = CalendarStore()
        store.duplicateDraft(try event(), to: work)
        XCTAssertEqual(try draft(store).attendees.map(\.email), ["c@x.com"])
    }

    func testDuplicateAllDayUsesInclusiveEnd() throws {
        let store = CalendarStore()
        let e = try event(allDay: true)
        store.duplicateDraft(e, to: work)
        let d = try draft(store)
        XCTAssertTrue(d.isAllDay)
        XCTAssertEqual(d.end, Calendar.current.date(byAdding: .day, value: -1, to: e.end))
    }
}
