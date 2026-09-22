import XCTest
@testable import EZCal

@MainActor
final class WorkWeekTests: XCTestCase {
    private func weekday(_ d: Date) -> Int { Calendar.current.component(.weekday, from: d) }  // 2 = Mon, 6 = Fri

    func testShowsMondayThroughFridayFromAnyDayOfTheWeek() {
        let cal = Calendar.current
        let monday = cal.date(from: DateComponents(year: 2026, month: 9, day: 21))!   // a Monday
        for offset in 0..<7 {                                                        // Mon…Sun
            let store = CalendarStore()
            store.mode = .workWeek
            store.anchor = cal.date(byAdding: .day, value: offset, to: monday)!
            let days = store.visibleDays
            XCTAssertEqual(days.count, 5, "offset \(offset)")
            XCTAssertEqual(weekday(days.first!), 2)
            XCTAssertEqual(weekday(days.last!), 6)
            XCTAssertTrue(cal.isDate(days.first!, inSameDayAs: monday), "offset \(offset) should stay in the same Mon–Sun week")
            XCTAssertEqual(cal.dateComponents([.day], from: store.fetchRange.lowerBound, to: store.fetchRange.upperBound).day, 5)
        }
    }

    func testStepMovesByWholeWeeksAndIgnoresWeekendSetting() {
        let store = CalendarStore()
        store.mode = .workWeek
        store.anchor = Calendar.current.date(from: DateComponents(year: 2026, month: 9, day: 23))!
        UserDefaults.standard.set(false, forKey: "showWeekends")
        defer { UserDefaults.standard.removeObject(forKey: "showWeekends") }
        store.step(1)
        XCTAssertEqual(store.visibleDays.count, 5)
        XCTAssertEqual(Calendar.current.component(.day, from: store.visibleDays.first!), 28)  // Mon Sep 28
        XCTAssertEqual(store.title, "Sep 28 – Oct 2, 2026")
    }
}
