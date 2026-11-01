import XCTest
@testable import EZCal

@MainActor
final class NavigationTests: XCTestCase {
    private func store(_ mode: ViewMode) -> CalendarStore {
        let s = CalendarStore()
        s.setMode(mode)
        s.goToday()
        return s
    }

    func testStepForwardThenBackReturnsToStart() {
        for mode in [ViewMode.day, .week, .workWeek, .month] {
            let s = store(mode)
            let (start, title) = (s.anchor, s.title)
            s.step(1)
            XCTAssertGreaterThan(s.anchor, start, "\(mode) should move forward")
            XCTAssertNotEqual(s.title, title, "\(mode)")
            s.step(-1)
            // Compared by what's shown: month arithmetic isn't exactly invertible (Oct 31 + 1 month - 1 month).
            XCTAssertEqual(s.title, title, "\(mode) should return to where it started")
            XCTAssertEqual(s.visibleDays, store(mode).visibleDays, "\(mode)")
        }
    }

    func testStepSizeMatchesViewMode() {
        let c = Calendar.current
        let day = store(.day), month = store(.month)
        let d0 = day.anchor, m0 = month.anchor
        day.step(1); month.step(1)
        XCTAssertEqual(c.dateComponents([.day], from: d0, to: day.anchor).day, 1)
        XCTAssertEqual(c.dateComponents([.month], from: m0, to: month.anchor).month, 1)
    }

    func testStepDayMovesOneDayInAnyMode() {
        let c = Calendar.current
        for mode in [ViewMode.day, .week, .month] {
            let s = store(mode)
            let start = s.anchor
            s.stepDay(1)
            XCTAssertEqual(c.dateComponents([.day], from: start, to: s.anchor).day, 1, "\(mode)")
        }
    }

    func testGoTodayAfterStepsComesBack() {
        for mode in [ViewMode.day, .week, .month] {
            let s = store(mode)
            let (title, days) = (s.title, s.visibleDays)
            s.step(3); s.step(-5)
            s.goToday()
            XCTAssertEqual(s.title, title, "\(mode)")
            XCTAssertEqual(s.visibleDays, days, "\(mode)")
        }
    }

    func testGoToShowsTheRequestedDay() {
        let c = Calendar.current
        let s = store(.day)
        let target = c.date(byAdding: .day, value: 40, to: Date())!
        s.goTo(target)
        XCTAssertTrue(s.visibleDays.contains { c.isDate($0, inSameDayAs: target) })
    }

    func testVisibleDayCountPerMode() {
        XCTAssertEqual(store(.day).visibleDays.count, 1)
        XCTAssertEqual(store(.workWeek).visibleDays.count, 5)
        XCTAssertEqual(store(.threeDay).visibleDays.count, 3)
    }

    // MARK: - 3 Day (#133), fixed dates so results never depend on today's weekday or time

    private func threeDayStore(anchoredAt day: Date) -> CalendarStore {
        let s = CalendarStore()
        s.setMode(.threeDay)
        s.anchor = day
        return s
    }

    func testThreeDayShowsThreeConsecutiveDaysFromAnchor() {
        let c = Calendar.current
        let start = c.date(from: DateComponents(year: 2026, month: 12, day: 30, hour: 17, minute: 45))!  // across a year boundary
        let s = threeDayStore(anchoredAt: start)
        let expected = (0..<3).map { c.date(byAdding: .day, value: $0, to: c.startOfDay(for: start))! }
        XCTAssertEqual(s.visibleDays, expected)
        XCTAssertEqual(ViewMode.threeDay.consecutiveDayCount, 3)
        XCTAssertEqual(ViewMode.day.consecutiveDayCount, 1)
        XCTAssertNil(ViewMode.week.consecutiveDayCount)
    }

    func testThreeDayStepsByThreeDaysAndBack() {
        let c = Calendar.current
        let start = c.date(from: DateComponents(year: 2026, month: 3, day: 1, hour: 9))!
        let s = threeDayStore(anchoredAt: start)
        s.step(1)
        XCTAssertEqual(c.dateComponents([.day], from: start, to: s.anchor).day, 3)
        XCTAssertEqual(c.component(.day, from: s.visibleDays.first!), 4)
        s.step(-2)
        XCTAssertEqual(c.dateComponents([.day], from: start, to: s.anchor).day, -3)
        s.step(1)
        XCTAssertEqual(s.anchor, start)
    }

    func testThreeDayFetchRangeCoversExactlyTheVisibleDays() {
        let c = Calendar.current
        let s = threeDayStore(anchoredAt: c.date(from: DateComponents(year: 2026, month: 5, day: 10, hour: 23))!)
        XCTAssertEqual(s.fetchRange.lowerBound, s.visibleDays.first)
        XCTAssertEqual(s.fetchRange.upperBound, c.endOfDay(s.visibleDays.last!))
    }

    func testThreeDayTitleIsADateRangeAndGoToShowsTarget() {
        let c = Calendar.current
        let s = threeDayStore(anchoredAt: c.date(from: DateComponents(year: 2026, month: 4, day: 29))!)
        XCTAssertTrue(s.title.contains("–"), s.title)
        let target = c.date(from: DateComponents(year: 2026, month: 8, day: 14, hour: 3))!
        s.goTo(target)
        XCTAssertTrue(s.visibleDays.contains { c.isDate($0, inSameDayAs: target) })
    }

    func testThreeDayViewModeBasics() {
        XCTAssertEqual(ViewMode(rawValue: "threeDay"), .threeDay)
        XCTAssertEqual(ViewMode.threeDay.title, "3 Day")
        XCTAssertTrue(ViewMode.allCases.contains(.threeDay))
    }
}
