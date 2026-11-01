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
    }
}
