import XCTest
@testable import EZCal

final class EventDragMathTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func date(_ h: Int, _ m: Int = 0, day: Int = 2) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 3, day: day, hour: h, minute: m))!
    }

    // MARK: snap

    func testSnapRoundsToNearest15Minutes() {
        XCTAssertEqual(EventDragMath.snap(minutes: 7), 0)      // < half of 15, rounds down
        XCTAssertEqual(EventDragMath.snap(minutes: 7.6), 15)   // > half of 15, rounds up
        XCTAssertEqual(EventDragMath.snap(minutes: -7.6), -15)
        XCTAssertEqual(EventDragMath.snap(minutes: -8), -15)
        XCTAssertEqual(EventDragMath.snap(minutes: 0), 0)
        XCTAssertEqual(EventDragMath.snap(minutes: 22), 15)
        XCTAssertEqual(EventDragMath.snap(minutes: 23), 30)
    }

    func testSnapCustomStep() {
        XCTAssertEqual(EventDragMath.snap(minutes: 20, step: 30), 30)
        XCTAssertEqual(EventDragMath.snap(minutes: 10, step: 30), 0)
    }

    // MARK: moved (drag to move)

    func testMovedPreservesDuration() {
        let start = date(9), end = date(10)
        let (s, e) = EventDragMath.moved(start: start, end: end, minutesDelta: 30, dayDelta: 0, cal: cal)
        XCTAssertEqual(s, date(9, 30))
        XCTAssertEqual(e.timeIntervalSince(s), end.timeIntervalSince(start))
        XCTAssertEqual(e, date(10, 30))
    }

    func testMovedAcrossDays() {
        let start = date(9), end = date(10, 30)
        let (s, e) = EventDragMath.moved(start: start, end: end, minutesDelta: 0, dayDelta: 2, cal: cal)
        XCTAssertEqual(cal.component(.day, from: s), 4)
        XCTAssertEqual(cal.component(.hour, from: s), 9)
        XCTAssertEqual(e.timeIntervalSince(s), 90 * 60)
    }

    func testMovedNegativeDelta() {
        let start = date(9), end = date(10)
        let (s, _) = EventDragMath.moved(start: start, end: end, minutesDelta: -45, dayDelta: 0, cal: cal)
        XCTAssertEqual(s, date(8, 15))
    }

    // MARK: resized (drag the bottom edge)

    func testResizedExtendsEnd() {
        let start = date(9), end = date(10)
        let (s, e) = EventDragMath.resized(start: start, end: end, minutesDelta: 45, cal: cal)
        XCTAssertEqual(s, start)
        XCTAssertEqual(e, date(10, 45))
    }

    func testResizedEnforcesMinimumDuration() {
        let start = date(9), end = date(9, 30)
        // Shrinking past the 15-minute minimum clamps to start + 15, not start.
        let (s, e) = EventDragMath.resized(start: start, end: end, minutesDelta: -60, cal: cal)
        XCTAssertEqual(s, start)
        XCTAssertEqual(e, date(9, 15))
    }

    func testResizedCustomMinimum() {
        let start = date(9), end = date(10)
        let (_, e) = EventDragMath.resized(start: start, end: end, minutesDelta: -120, minimumMinutes: 30, cal: cal)
        XCTAssertEqual(e, date(9, 30))
    }

    func testResizedNeverMovesStart() {
        let start = date(9), end = date(11)
        let (s, _) = EventDragMath.resized(start: start, end: end, minutesDelta: -30, cal: cal)
        XCTAssertEqual(s, start)
    }
}
