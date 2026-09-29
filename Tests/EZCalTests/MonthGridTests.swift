import XCTest
@testable import EZCal

final class MonthGridTests: XCTestCase {
    private func makeCal(firstWeekday: Int) -> Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "America/Denver")!
        c.firstWeekday = firstWeekday
        return c
    }
    private func date(_ cal: Calendar, _ y: Int, _ m: Int, _ d: Int, _ h: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h))!
    }

    func testWeekIndexRoundTripAndWeekdayAlignment() {
        for fw in [1, 2] {
            let cal = makeCal(firstWeekday: fw)
            let g = MonthGrid(cal: cal)
            for offset in stride(from: -900, through: 900, by: 13) {
                let d = cal.date(byAdding: .day, value: offset, to: date(cal, 2026, 9, 29, 15))!
                let w = g.weekIndex(of: d)
                let start = g.weekStart(w)
                XCTAssertEqual(cal.component(.weekday, from: start), fw)
                XCTAssertLessThanOrEqual(start, d)
                XCTAssertGreaterThan(g.weekStart(w + 1), d)
            }
        }
    }

    func testDayColumnsAreConsecutiveAcrossDST() {
        let cal = makeCal(firstWeekday: 1)
        let g = MonthGrid(cal: cal)
        let w = g.weekIndex(of: date(cal, 2026, 3, 8))   // US spring-forward Sunday
        for c in 0..<7 {
            let d = g.day(week: w, column: c)
            XCTAssertEqual(d, cal.startOfDay(for: d))
            XCTAssertEqual(cal.component(.day, from: d), 8 + c)
        }
    }

    func testFirstWeekOfEveryMonthMapsBackToThatMonth() {
        for fw in 1...7 {
            let g = MonthGrid(cal: makeCal(firstWeekday: fw))
            for y in 2020...2032 {
                for m in 1...12 {
                    let key = y * 12 + m - 1
                    let w = g.firstWeek(ofMonth: key)
                    XCTAssertEqual(g.monthKey(forWeek: w), key, "fw \(fw) \(y)-\(m)")
                    XCTAssertNotEqual(g.monthKey(forWeek: w - 1), key)   // it is the FIRST such week
                }
            }
        }
    }

    func testMonthKeyForWeekUsesMajorityOfTheWeek() {
        let cal = makeCal(firstWeekday: 1)   // Sunday start
        let g = MonthGrid(cal: cal)
        // Week of Sun Aug 30 - Sat Sep 5 2026: 4th day is Wed Sep 2 -> September.
        XCTAssertEqual(g.monthKey(forWeek: g.weekIndex(of: date(cal, 2026, 8, 30))), 2026 * 12 + 8)
        // Week of Sun Jun 28 - Sat Jul 4 2026: 4th day is Wed Jul 1 -> July.
        XCTAssertEqual(g.monthKey(forWeek: g.weekIndex(of: date(cal, 2026, 6, 30))), 2026 * 12 + 6)
        // Week of Sun Sep 27 - Sat Oct 3: 4 of 7 days are September (4th day Wed Sep 30).
        XCTAssertEqual(g.monthKey(forWeek: g.weekIndex(of: date(cal, 2026, 9, 29))), 2026 * 12 + 8)
    }

    func testAnchorMoveClampsDay() {
        let cal = makeCal(firstWeekday: 1)
        let g = MonthGrid(cal: cal)
        let moved = g.anchor(date(cal, 2026, 1, 31), movedToMonth: 2026 * 12 + 1)   // Feb
        XCTAssertEqual(cal.component(.month, from: moved), 2)
        XCTAssertEqual(cal.component(.day, from: moved), 28)
        let same = g.anchor(date(cal, 2026, 9, 15, 13), movedToMonth: 2026 * 12 + 10)
        XCTAssertEqual(cal.component(.month, from: same), 11)
        XCTAssertEqual(cal.component(.day, from: same), 15)
    }

    func testFetchRangeCoversPrevCurrentAndNextMonthInWholeWeeks() {
        let cal = makeCal(firstWeekday: 1)
        let g = MonthGrid(cal: cal)
        let r = g.fetchRange(aroundMonth: 2026 * 12 + 8)   // September 2026
        XCTAssertLessThanOrEqual(r.lowerBound, date(cal, 2026, 8, 1))
        XCTAssertEqual(cal.component(.weekday, from: r.lowerBound), 1)
        XCTAssertGreaterThanOrEqual(r.upperBound, date(cal, 2026, 11, 1))
        XCTAssertLessThan(r.upperBound, date(cal, 2026, 11, 3))
    }

    func testWindowRecentersOnlyNearEdges() {
        let w = WeekWindow(center: 1000)
        XCTAssertNil(w.recentered(forTop: 1000))
        XCTAssertNil(w.recentered(forTop: 1000 + WeekWindow.radius - WeekWindow.margin - 1))
        XCTAssertEqual(w.recentered(forTop: 1000 + WeekWindow.radius - 5)?.center, 1000 + WeekWindow.radius - 5)
        XCTAssertEqual(w.recentered(forTop: 1000 - WeekWindow.radius + 2)?.center, 1000 - WeekWindow.radius + 2)
    }

    // MARK: - DayEventIndex

    private func event(_ id: String, _ start: Date, _ end: Date, allDay: Bool = false) -> CalEvent {
        CalEvent(id: id, eventId: id, sourceId: "s", calendarId: "s", accountId: "a", uid: id, title: id,
                 start: start, end: end, isAllDay: allDay,
                 location: "", notes: "", attendees: [], htmlLink: nil, meetingURL: nil, colorHex: "#fff",
                 sourceName: "s", ownerName: nil, isOverlay: false, canEdit: true, isBusyOnly: false,
                 isRecurring: false, zoomMeetingID: nil, isTentative: false, isDeclined: false)
    }

    func testIndexMatchesNaiveFilter() {
        let cal = makeCal(firstWeekday: 1)
        let base = date(cal, 2026, 9, 10)
        var evs: [CalEvent] = []
        evs.append(event("a", cal.date(byAdding: .hour, value: 14, to: base)!, cal.date(byAdding: .hour, value: 15, to: base)!))
        evs.append(event("b", cal.date(byAdding: .hour, value: 9, to: base)!, cal.date(byAdding: .hour, value: 10, to: base)!))
        evs.append(event("zero", cal.date(byAdding: .hour, value: 11, to: base)!, cal.date(byAdding: .hour, value: 11, to: base)!))
        // Multi-day all-day: Sep 12 through Sep 14 inclusive (end exclusive Sep 15).
        evs.append(event("trip", date(cal, 2026, 9, 12), date(cal, 2026, 9, 15), allDay: true))
        // Timed event crossing midnight.
        evs.append(event("late", date(cal, 2026, 9, 20, 23), date(cal, 2026, 9, 21, 1)))
        // Ends exactly at midnight: must not appear on the next day.
        evs.append(event("edge", date(cal, 2026, 9, 25, 22), date(cal, 2026, 9, 26, 0)))

        let idx = DayEventIndex(events: evs, cal: cal)
        for off in 0..<30 {
            let day = cal.date(byAdding: .day, value: off, to: date(cal, 2026, 9, 1))!
            let s = cal.startOfDay(for: day), e = cal.endOfDay(day)
            let hit = evs.filter { $0.start < e && max($0.end, $0.start.addingTimeInterval(1)) > s }
            let got = idx.events(on: day.addingTimeInterval(3600 * 5))
            XCTAssertEqual(got.allDay.map(\.id), hit.filter(\.isAllDay).sorted { $0.start < $1.start }.map(\.id), "day \(off)")
            XCTAssertEqual(got.timed.map(\.id), hit.filter { !$0.isAllDay }.sorted { $0.start < $1.start }.map(\.id), "day \(off)")
        }
        XCTAssertEqual(idx.events(on: date(cal, 2026, 9, 10)).timed.map(\.id), ["b", "zero", "a"])
        XCTAssertEqual(idx.events(on: date(cal, 2026, 9, 13)).allDay.map(\.id), ["trip"])
        XCTAssertTrue(idx.events(on: date(cal, 2026, 9, 26)).timed.isEmpty)
    }
}
