import XCTest
@testable import EZCal

/// #139: the grid must place events by wall clock, so 9 AM sits on the 9 AM row on 23/24/25-hour days.
final class GridTimeTests: XCTestCase {
    private func makeCal(_ id: String) -> Calendar {
        var c = Calendar(identifier: .gregorian); c.timeZone = TimeZone(identifier: id)!; return c
    }
    private lazy var denver = makeCal("America/Denver")
    private lazy var phoenix = makeCal("America/Phoenix")   // no DST
    private let hh = 60.0   // 1 point per minute

    private func at(_ cal: Calendar, _ y: Int, _ mo: Int, _ d: Int, _ h: Int, _ mi: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: mo, day: d, hour: h, minute: mi))!
    }

    func testNormalDay() {
        let day = at(denver, 2026, 10, 15, 0)
        XCTAssertEqual(GridTime.y(of: at(denver, 2026, 10, 15, 9), on: day, hourHeight: hh, cal: denver), 540)
        XCTAssertEqual(GridTime.height(from: at(denver, 2026, 10, 15, 9), to: at(denver, 2026, 10, 15, 10, 30), hourHeight: hh, cal: denver), 90)
    }

    func testNonDSTZoneOnUSChangeDay() {
        let day = at(phoenix, 2026, 11, 1, 0)
        XCTAssertEqual(GridTime.y(of: at(phoenix, 2026, 11, 1, 9), on: day, hourHeight: hh, cal: phoenix), 540)
        XCTAssertEqual(GridTime.y(of: at(phoenix, 2026, 11, 1, 23, 30), on: day, hourHeight: hh, cal: phoenix), 1410)
    }

    func testFallBackDay25Hours() {
        let day = at(denver, 2026, 11, 1, 0)
        XCTAssertEqual(denver.dateInterval(of: .day, for: day)!.duration, 25 * 3600)
        // Before the change: unchanged. After it: wall 9 AM is the 9 AM row, though 10 hours have elapsed.
        XCTAssertEqual(GridTime.y(of: at(denver, 2026, 11, 1, 0, 30), on: day, hourHeight: hh, cal: denver), 30)
        let nine = at(denver, 2026, 11, 1, 9)
        XCTAssertEqual(nine.timeIntervalSince(day), 10 * 3600)
        XCTAssertEqual(GridTime.y(of: nine, on: day, hourHeight: hh, cal: denver), 540)
        XCTAssertEqual(GridTime.height(from: nine, to: at(denver, 2026, 11, 1, 10), hourHeight: hh, cal: denver), 60)
        XCTAssertEqual(GridTime.y(of: at(denver, 2026, 11, 1, 23, 45), on: day, hourHeight: hh, cal: denver), 1425)
        // Both 1:30s land on the 1 AM row.
        let first = day.addingTimeInterval(1.5 * 3600), second = day.addingTimeInterval(2.5 * 3600)
        XCTAssertEqual(GridTime.y(of: first, on: day, hourHeight: hh, cal: denver), 90)
        XCTAssertEqual(GridTime.y(of: second, on: day, hourHeight: hh, cal: denver), 90)
    }

    func testSpringForwardDay23Hours() {
        let day = at(denver, 2026, 3, 8, 0)
        XCTAssertEqual(denver.dateInterval(of: .day, for: day)!.duration, 23 * 3600)
        let nine = at(denver, 2026, 3, 8, 9)
        XCTAssertEqual(nine.timeIntervalSince(day), 8 * 3600)
        XCTAssertEqual(GridTime.y(of: nine, on: day, hourHeight: hh, cal: denver), 540)
        XCTAssertEqual(GridTime.y(of: at(denver, 2026, 3, 8, 1, 30), on: day, hourHeight: hh, cal: denver), 90)
        XCTAssertEqual(GridTime.y(of: at(denver, 2026, 3, 8, 3), on: day, hourHeight: hh, cal: denver), 180)
        XCTAssertEqual(GridTime.y(of: at(denver, 2027, 3, 14, 9), on: at(denver, 2027, 3, 14, 0), hourHeight: hh, cal: denver), 540)
    }

    func testEventSpanningTheChange() {
        // Spring forward: 1:00 -> 4:00 wall is 2 real hours but draws 3 rows, covering the empty 2 AM row.
        let day = at(denver, 2026, 3, 8, 0)
        let s = at(denver, 2026, 3, 8, 1), e = at(denver, 2026, 3, 8, 4)
        XCTAssertEqual(e.timeIntervalSince(s), 2 * 3600)
        XCTAssertEqual(GridTime.y(of: s, on: day, hourHeight: hh, cal: denver), 60)
        XCTAssertEqual(GridTime.height(from: s, to: e, hourHeight: hh, cal: denver), 180)
        // Fall back: 0:30 -> 3:00 wall (3.5 real hours) draws 2.5 rows; never negative.
        let fday = at(denver, 2026, 11, 1, 0)
        let fs = at(denver, 2026, 11, 1, 0, 30), fe = at(denver, 2026, 11, 1, 3)
        XCTAssertEqual(GridTime.height(from: fs, to: fe, hourHeight: hh, cal: denver), 150)
        let inRepeat = fday.addingTimeInterval(2.5 * 3600)   // 1:30 second time
        XCTAssertEqual(GridTime.height(from: fday.addingTimeInterval(1.75 * 3600), to: inRepeat, hourHeight: hh, cal: denver), 0)
    }

    func testRoundTrip() {
        for (y, mo, d) in [(2026, 11, 1), (2026, 3, 8), (2027, 3, 14), (2026, 10, 15)] {
            let day = at(denver, y, mo, d, 0)
            for m in stride(from: 0, to: 1440, by: 15) {
                if (mo == 3 && m >= 120 && m < 180) { continue }          // skipped hour
                if (mo == 11 && m >= 60 && m < 120) { continue }          // repeated hour (first occurrence is fine, skip)
                let date = GridTime.date(minutes: m, on: day, cal: denver)
                XCTAssertEqual(GridTime.minutes(of: date, on: day, cal: denver), Double(m), "\(y)-\(mo)-\(d) \(m)")
                let yy = GridTime.y(of: date, on: day, hourHeight: 56, cal: denver)
                XCTAssertEqual(GridTime.date(atY: yy, on: day, hourHeight: 56, cal: denver), date)
            }
        }
        // Skipped hour resolves forward, repeated hour to the first occurrence.
        let spring = at(denver, 2026, 3, 8, 0)
        XCTAssertEqual(GridTime.minutes(of: GridTime.date(minutes: 150, on: spring, cal: denver), on: spring, cal: denver), 180)
        let fall = at(denver, 2026, 11, 1, 0)
        XCTAssertEqual(GridTime.date(minutes: 90, on: fall, cal: denver), fall.addingTimeInterval(1.5 * 3600))
    }

    func testDragShiftIsWallClock() {
        let day = at(denver, 2026, 11, 1, 0)
        let s = at(denver, 2026, 11, 1, 9), e = at(denver, 2026, 11, 1, 10)
        let m = EventDragMath.moved(start: s, end: e, minutesDelta: 30, dayDelta: 0, cal: denver)
        XCTAssertEqual(GridTime.minutes(of: m.start, on: day, cal: denver), 570)
        XCTAssertEqual(m.end.timeIntervalSince(m.start), 3600)
        let r = EventDragMath.resized(start: s, end: e, minutesDelta: 60, cal: denver)
        XCTAssertEqual(GridTime.minutes(of: r.end, on: day, cal: denver), 660)
        // Dragging 4 AM down by 15 minutes on spring-forward day is 4:15, no matter the gap above it.
        let sday = at(denver, 2026, 3, 8, 0)
        let m2 = EventDragMath.moved(start: at(denver, 2026, 3, 8, 4), end: at(denver, 2026, 3, 8, 5), minutesDelta: 15, dayDelta: 0, cal: denver)
        XCTAssertEqual(GridTime.minutes(of: m2.start, on: sday, cal: denver), 255)
    }
}
