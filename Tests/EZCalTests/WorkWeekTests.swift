import XCTest
@testable import EZCal

@MainActor
final class WorkWeekTests: XCTestCase {
    private func weekday(_ d: Date) -> Int { Calendar.current.component(.weekday, from: d) }  // 2 = Mon, 6 = Fri

    /// Work Week scrolls continuously: `anchor` is the leftmost day and five weekday columns follow it.
    func testShowsFiveWeekdaysStartingAtTheAnchorSkippingWeekends() {
        let cal = Calendar.current
        let monday = cal.date(from: DateComponents(year: 2026, month: 9, day: 21))!   // a Monday
        for offset in 0..<7 {                                                        // Mon...Sun
            let store = CalendarStore()
            store.mode = .workWeek
            store.anchor = cal.date(byAdding: .day, value: offset, to: monday)!
            let days = store.visibleDays
            XCTAssertEqual(days.count, 5, "offset \(offset)")
            XCTAssertTrue(days.allSatisfy { (2...6).contains(weekday($0)) }, "offset \(offset) must contain no weekend day")
            // Sat/Sun anchors start on the following Monday; weekday anchors start on themselves.
            let expectedFirst = offset >= 5 ? 7 : offset
            XCTAssertTrue(cal.isDate(days.first!, inSameDayAs: cal.date(byAdding: .day, value: expectedFirst, to: monday)!), "offset \(offset)")
            let range = store.fetchRange
            XCTAssertLessThanOrEqual(range.lowerBound, days.first!)
            XCTAssertGreaterThan(range.upperBound, days.last!)
        }
    }

    func testStepMovesByWholeWeeksAndIgnoresWeekendSetting() {
        let store = CalendarStore()
        store.mode = .workWeek
        store.anchor = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 21))!   // Mon
        UserDefaults.standard.set(false, forKey: "showWeekends")
        defer { UserDefaults.standard.removeObject(forKey: "showWeekends") }
        store.step(1)
        XCTAssertEqual(store.visibleDays.count, 5)
        XCTAssertEqual(Calendar.current.component(.day, from: store.visibleDays.first!), 28)  // Mon Sep 28
        XCTAssertEqual(store.title, "Sep 28 – Oct 2, 2026")
    }

    func testGoToTodayAlignsToTheWeekStartInWeekModes() {
        let cal = Calendar.current
        let store = CalendarStore()
        store.mode = .workWeek
        store.goTo(cal.date(from: DateComponents(year: 2026, month: 9, day: 24))!)     // Thu
        XCTAssertEqual(cal.component(.day, from: store.anchor), 21)                     // Mon Sep 21
    }

    func testMiniCalendarClickMakesTheClickedDayLeadInWeekModes() {
        let cal = Calendar.current
        let store = CalendarStore()
        store.mode = .workWeek
        store.anchor = cal.date(from: DateComponents(year: 2026, month: 9, day: 21))!   // Mon
        store.goToDay(cal.date(from: DateComponents(year: 2026, month: 9, day: 24))!)   // Thu, same week
        XCTAssertEqual(cal.component(.day, from: store.anchor), 24)
        store.goToDay(cal.date(from: DateComponents(year: 2026, month: 9, day: 26))!)   // Sat, hidden column
        XCTAssertEqual(cal.component(.day, from: store.anchor), 28)                     // -> Mon
    }

    /// Swipe/scroll navigation should glide a day at a time, never a whole week or month, regardless
    /// of which view is showing.
    func testStepDayMovesExactlyOneDayRegardlessOfMode() {
        let cal = Calendar.current
        let wednesday = cal.date(from: DateComponents(year: 2026, month: 9, day: 23))!
        for mode: ViewMode in [.day, .workWeek, .week, .month] {
            let store = CalendarStore()
            store.mode = mode
            store.anchor = wednesday
            store.stepDay(1)
            XCTAssertEqual(cal.dateComponents([.day], from: wednesday, to: store.anchor).day, 1, "\(mode)")
            store.stepDay(-3)
            XCTAssertEqual(cal.dateComponents([.day], from: wednesday, to: store.anchor).day, -2, "\(mode)")
        }
    }
}
