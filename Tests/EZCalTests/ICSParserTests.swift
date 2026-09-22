import XCTest
@testable import EZCal

final class ICSParserTests: XCTestCase {
    private var utc: Calendar {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }

    private func utcDate(_ y: Int, _ m: Int, _ d: Int, _ hh: Int = 0, _ mm: Int = 0) -> Date {
        utc.date(from: DateComponents(year: y, month: m, day: d, hour: hh, minute: mm))!
    }

    // MARK: Line unfolding

    func testUnfoldsWrappedLines() {
        // RFC 5545: a line starting with a space or tab continues the previous physical line.
        let text = "SUMMARY:Long meeting\r\n  title that wraps\r\nLOCATION:Room 1\r\n"
        let lines = ICSParser.unfold(text)
        XCTAssertEqual(lines, ["SUMMARY:Long meeting title that wraps", "LOCATION:Room 1"])
    }

    func testUnfoldsTabContinuation() {
        let text = "DESCRIPTION:one\n\ttwo"
        XCTAssertEqual(ICSParser.unfold(text), ["DESCRIPTION:onetwo"])
    }

    // MARK: Basic VEVENT parsing

    func testParsesBasicUTCEvent() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:1@example.com
        SUMMARY:Team sync
        DTSTART:20260115T090000Z
        DTEND:20260115T093000Z
        LOCATION:HQ
        DESCRIPTION:Weekly check-in
        URL:https://example.com/e/1
        END:VEVENT
        END:VCALENDAR
        """
        let events = ICSParser.parse(ics)
        XCTAssertEqual(events.count, 1)
        let e = events[0]
        XCTAssertEqual(e.uid, "1@example.com")
        XCTAssertEqual(e.summary, "Team sync")
        XCTAssertEqual(e.location, "HQ")
        XCTAssertEqual(e.description, "Weekly check-in")
        XCTAssertEqual(e.url, URL(string: "https://example.com/e/1"))
        XCTAssertFalse(e.isAllDay)
        XCTAssertEqual(e.start, utcDate(2026, 1, 15, 9, 0))
        XCTAssertEqual(e.end, utcDate(2026, 1, 15, 9, 30))
    }

    func testIgnoresNestedComponentsLikeValarm() {
        let ics = """
        BEGIN:VCALENDAR
        BEGIN:VEVENT
        UID:withalarm@example.com
        SUMMARY:Has an alarm
        DTSTART:20260101T100000Z
        DTEND:20260101T110000Z
        BEGIN:VALARM
        ACTION:DISPLAY
        TRIGGER:-PT15M
        END:VALARM
        END:VEVENT
        END:VCALENDAR
        """
        let events = ICSParser.parse(ics)
        XCTAssertEqual(events.count, 1)
        XCTAssertEqual(events[0].summary, "Has an alarm")
    }

    func testSkipsCancelledEvents() {
        let ics = """
        BEGIN:VEVENT
        UID:c1@example.com
        SUMMARY:Cancelled
        DTSTART:20260101T100000Z
        STATUS:CANCELLED
        END:VEVENT
        BEGIN:VEVENT
        UID:c2@example.com
        SUMMARY:Still on
        DTSTART:20260101T110000Z
        END:VEVENT
        """
        let events = ICSParser.parse(ics)
        XCTAssertEqual(events.map(\.uid), ["c2@example.com"])
    }

    func testMissingEndDefaultsToOneHour() {
        let ics = """
        BEGIN:VEVENT
        UID:noend@example.com
        SUMMARY:Point event
        DTSTART:20260101T100000Z
        END:VEVENT
        """
        let e = ICSParser.parse(ics)[0]
        XCTAssertEqual(e.end.timeIntervalSince(e.start), 3600)
    }

    // MARK: Escaped text

    func testUnescapesText() {
        let ics = #"""
        BEGIN:VEVENT
        UID:esc@example.com
        SUMMARY:Comma\, semicolon\; and backslash\\
        DESCRIPTION:Line one\nLine two
        DTSTART:20260101T100000Z
        END:VEVENT
        """#
        let e = ICSParser.parse(ics)[0]
        XCTAssertEqual(e.summary, "Comma, semicolon; and backslash\\")
        XCTAssertEqual(e.description, "Line one\nLine two")
    }

    // MARK: All-day (VALUE=DATE)

    func testAllDayEvent() {
        let ics = """
        BEGIN:VEVENT
        UID:allday@example.com
        SUMMARY:Holiday
        DTSTART;VALUE=DATE:20260704
        DTEND;VALUE=DATE:20260705
        END:VEVENT
        """
        let e = ICSParser.parse(ics)[0]
        XCTAssertTrue(e.isAllDay)
        // All-day boundaries are local midnight, matching RFC3339.parseDay used elsewhere in the app.
        XCTAssertEqual(e.start, RFC3339.parseDay("2026-07-04"))
        XCTAssertEqual(e.end, RFC3339.parseDay("2026-07-05"))
    }

    func testAllDayInferredFromBareDateValue() {
        // Some feeds omit VALUE=DATE when the value is unambiguously a bare date.
        let ics = "BEGIN:VEVENT\nUID:bare@example.com\nSUMMARY:Bare date\nDTSTART:20260320\nEND:VEVENT"
        let e = ICSParser.parse(ics)[0]
        XCTAssertTrue(e.isAllDay)
        XCTAssertEqual(e.start, RFC3339.parseDay("2026-03-20"))
    }

    // MARK: TZID

    func testTZIDIsHonored() {
        let ics = """
        BEGIN:VEVENT
        UID:tz@example.com
        SUMMARY:New York meeting
        DTSTART;TZID=America/New_York:20260115T090000
        DTEND;TZID=America/New_York:20260115T100000
        END:VEVENT
        """
        let e = ICSParser.parse(ics)[0]
        // 9am US Eastern (EST, UTC-5) in January is 14:00 UTC.
        XCTAssertEqual(e.start, utcDate(2026, 1, 15, 14, 0))
        XCTAssertEqual(e.timeZone.identifier, "America/New_York")
    }

    func testUnknownTZIDFallsBackWithoutCrashing() {
        let ics = "BEGIN:VEVENT\nUID:badtz@example.com\nSUMMARY:x\nDTSTART;TZID=Not/AZone:20260101T100000\nEND:VEVENT"
        XCTAssertEqual(ICSParser.parse(ics).count, 1)
    }

    // MARK: RRULE expansion

    func testDailyRecurrenceWithCount() {
        let ics = """
        BEGIN:VEVENT
        UID:daily@example.com
        SUMMARY:Standup
        DTSTART:20260105T090000Z
        DTEND:20260105T091500Z
        RRULE:FREQ=DAILY;COUNT=3
        END:VEVENT
        """
        let e = ICSParser.parse(ics)[0]
        let range = utcDate(2026, 1, 1)..<utcDate(2026, 2, 1)
        let occ = e.recurrence!.occurrences(seriesStart: e.start, timeZone: e.timeZone, range: range)
        XCTAssertEqual(occ, [utcDate(2026, 1, 5, 9), utcDate(2026, 1, 6, 9), utcDate(2026, 1, 7, 9)])
    }

    func testCountIsRelativeToSeriesStartNotQueryRange() {
        // A 3-occurrence series queried for a window that starts after all three should yield nothing,
        // proving COUNT is tracked from DTSTART and not reset per query range.
        let ics = """
        BEGIN:VEVENT
        UID:daily2@example.com
        SUMMARY:Standup
        DTSTART:20260105T090000Z
        RRULE:FREQ=DAILY;COUNT=3
        END:VEVENT
        """
        let e = ICSParser.parse(ics)[0]
        let farRange = utcDate(2026, 6, 1)..<utcDate(2026, 7, 1)
        XCTAssertTrue(e.recurrence!.occurrences(seriesStart: e.start, timeZone: e.timeZone, range: farRange).isEmpty)
    }

    func testWeeklyByDayInterval() {
        // Every other week, Monday/Wednesday/Friday, starting Monday Jan 5 2026.
        let ics = """
        BEGIN:VEVENT
        UID:weekly@example.com
        SUMMARY:Gym
        DTSTART:20260105T060000Z
        DTEND:20260105T070000Z
        RRULE:FREQ=WEEKLY;INTERVAL=2;BYDAY=MO,WE,FR
        END:VEVENT
        """
        let e = ICSParser.parse(ics)[0]
        let range = utcDate(2026, 1, 1)..<utcDate(2026, 2, 1)
        let occ = e.recurrence!.occurrences(seriesStart: e.start, timeZone: e.timeZone, range: range)
        // Week of Jan 5: Mon 5, Wed 7, Fri 9. Next occurrence (interval=2) is the week of Jan 19: Mon 19, Wed 21, Fri 23.
        XCTAssertEqual(occ, [
            utcDate(2026, 1, 5, 6), utcDate(2026, 1, 7, 6), utcDate(2026, 1, 9, 6),
            utcDate(2026, 1, 19, 6), utcDate(2026, 1, 21, 6), utcDate(2026, 1, 23, 6),
        ])
    }

    func testWeeklyWithoutByDayRepeatsSameWeekday() {
        let ics = """
        BEGIN:VEVENT
        UID:weekly2@example.com
        SUMMARY:1:1
        DTSTART:20260106T150000Z
        RRULE:FREQ=WEEKLY;COUNT=3
        END:VEVENT
        """
        let e = ICSParser.parse(ics)[0]
        let range = utcDate(2026, 1, 1)..<utcDate(2026, 3, 1)
        let occ = e.recurrence!.occurrences(seriesStart: e.start, timeZone: e.timeZone, range: range)
        XCTAssertEqual(occ, [utcDate(2026, 1, 6, 15), utcDate(2026, 1, 13, 15), utcDate(2026, 1, 20, 15)])
    }

    func testMonthlySameDayOfMonth() {
        let ics = """
        BEGIN:VEVENT
        UID:monthly@example.com
        SUMMARY:Rent
        DTSTART:20260131T000000Z
        RRULE:FREQ=MONTHLY;COUNT=6
        END:VEVENT
        """
        let e = ICSParser.parse(ics)[0]
        let range = utcDate(2026, 1, 1)..<utcDate(2026, 8, 1)
        let occ = e.recurrence!.occurrences(seriesStart: e.start, timeZone: e.timeZone, range: range)
        // Jan 31 exists; Feb/Apr/Jun have no 31st and RFC 5545 says skip those months entirely.
        XCTAssertEqual(occ, [utcDate(2026, 1, 31), utcDate(2026, 3, 31), utcDate(2026, 5, 31), utcDate(2026, 7, 31)])
    }

    func testMonthlyByDayOrdinal() {
        // "Second Tuesday of the month" — a common board-game-night / sports-league pattern.
        let ics = """
        BEGIN:VEVENT
        UID:monthlyord@example.com
        SUMMARY:League night
        DTSTART:20260113T190000Z
        RRULE:FREQ=MONTHLY;BYDAY=2TU;COUNT=3
        END:VEVENT
        """
        let e = ICSParser.parse(ics)[0]
        XCTAssertEqual(e.start, utcDate(2026, 1, 13, 19))   // Jan 13 2026 is indeed the second Tuesday
        let range = utcDate(2026, 1, 1)..<utcDate(2026, 5, 1)
        let occ = e.recurrence!.occurrences(seriesStart: e.start, timeZone: e.timeZone, range: range)
        XCTAssertEqual(occ, [utcDate(2026, 1, 13, 19), utcDate(2026, 2, 10, 19), utcDate(2026, 3, 10, 19)])
    }

    func testYearlyRecurrence() {
        let ics = """
        BEGIN:VEVENT
        UID:yearly@example.com
        SUMMARY:Anniversary
        DTSTART;VALUE=DATE:20200704
        RRULE:FREQ=YEARLY
        END:VEVENT
        """
        let e = ICSParser.parse(ics)[0]
        let range = RFC3339.parseDay("2025-01-01")!..<RFC3339.parseDay("2028-01-01")!
        let occ = e.recurrence!.occurrences(seriesStart: e.start, timeZone: e.timeZone, range: range)
        XCTAssertEqual(occ, [RFC3339.parseDay("2025-07-04")!, RFC3339.parseDay("2026-07-04")!, RFC3339.parseDay("2027-07-04")!])
    }

    func testUntilStopsExpansion() {
        let ics = """
        BEGIN:VEVENT
        UID:until@example.com
        SUMMARY:Sprint standup
        DTSTART:20260105T090000Z
        RRULE:FREQ=DAILY;UNTIL=20260107T090000Z
        END:VEVENT
        """
        let e = ICSParser.parse(ics)[0]
        let range = utcDate(2026, 1, 1)..<utcDate(2026, 2, 1)
        let occ = e.recurrence!.occurrences(seriesStart: e.start, timeZone: e.timeZone, range: range)
        XCTAssertEqual(occ, [utcDate(2026, 1, 5, 9), utcDate(2026, 1, 6, 9), utcDate(2026, 1, 7, 9)])
    }

    func testRangeFiltersOccurrencesOutsideWindow() {
        let ics = """
        BEGIN:VEVENT
        UID:ranged@example.com
        SUMMARY:Daily thing
        DTSTART:20260101T090000Z
        RRULE:FREQ=DAILY;COUNT=30
        END:VEVENT
        """
        let e = ICSParser.parse(ics)[0]
        let range = utcDate(2026, 1, 10)..<utcDate(2026, 1, 13)
        let occ = e.recurrence!.occurrences(seriesStart: e.start, timeZone: e.timeZone, range: range)
        XCTAssertEqual(occ, [utcDate(2026, 1, 10, 9), utcDate(2026, 1, 11, 9), utcDate(2026, 1, 12, 9)])
    }

    // MARK: EXDATE

    func testExdateExcludesInstance() {
        let ics = """
        BEGIN:VEVENT
        UID:exd@example.com
        SUMMARY:Standup
        DTSTART:20260105T090000Z
        RRULE:FREQ=DAILY;COUNT=5
        EXDATE:20260107T090000Z
        END:VEVENT
        """
        let e = ICSParser.parse(ics)[0]
        XCTAssertEqual(e.exceptionDates, [utcDate(2026, 1, 7, 9)])
        let range = utcDate(2026, 1, 1)..<utcDate(2026, 2, 1)
        let occ = e.recurrence!.occurrences(seriesStart: e.start, timeZone: e.timeZone, range: range).filter { !e.exceptionDates.contains($0) }
        XCTAssertEqual(occ, [utcDate(2026, 1, 5, 9), utcDate(2026, 1, 6, 9), utcDate(2026, 1, 8, 9), utcDate(2026, 1, 9, 9)])
    }

    // MARK: Multiple events / real-world-shaped feed

    func testParsesMultipleEventsFromOneFeed() {
        let ics = """
        BEGIN:VCALENDAR
        VERSION:2.0
        PRODID:-//Example//Sports//EN
        BEGIN:VTIMEZONE
        TZID:America/New_York
        END:VTIMEZONE
        BEGIN:VEVENT
        UID:game1@example.com
        SUMMARY:Home vs. Rivals
        DTSTART;TZID=America/New_York:20260212T190000
        DTEND;TZID=America/New_York:20260212T213000
        LOCATION:Main Arena
        END:VEVENT
        BEGIN:VEVENT
        UID:game2@example.com
        SUMMARY:Away vs. Champions
        DTSTART;TZID=America/New_York:20260219T190000
        DTEND;TZID=America/New_York:20260219T213000
        LOCATION:Away Arena
        END:VEVENT
        END:VCALENDAR
        """
        let events = ICSParser.parse(ics)
        XCTAssertEqual(events.map(\.uid), ["game1@example.com", "game2@example.com"])
        XCTAssertEqual(events.map(\.location), ["Main Arena", "Away Arena"])
    }

    func testMalformedFeedIsToleratedNotCrashing() {
        let ics = "NOT AN ICS FILE AT ALL\nBEGIN:VEVENT\nSUMMARY:Missing UID and DTSTART\nEND:VEVENT"
        XCTAssertEqual(ICSParser.parse(ics).count, 0)   // no UID/DTSTART -> dropped, no crash
    }
}
