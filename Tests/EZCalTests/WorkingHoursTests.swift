import XCTest
@testable import EZCal

final class WorkingHoursTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d))!
    }

    // MARK: Day-of-week encoding

    func testDayEncodingRoundTrips() {
        let days: Set<Int> = [2, 4, 6]
        XCTAssertEqual(WorkingHours.decodeDays(WorkingHours.encodeDays(days)), days)
    }

    func testDecodeIgnoresJunkAndOutOfRangeValues() {
        XCTAssertEqual(WorkingHours.decodeDays("2, 3,x,9,0,5"), [2, 3, 5])
        XCTAssertEqual(WorkingHours.decodeDays(""), [])
    }

    // MARK: Clamping

    func testInitClampsEndToAfterStart() {
        let h = WorkingHours(days: [2], startMinute: 600, endMinute: 500)
        XCTAssertGreaterThan(h.endMinute, h.startMinute)
    }

    func testInitClampsToWithinADay() {
        let h = WorkingHours(days: [2], startMinute: -30, endMinute: 24 * 60 + 90)
        XCTAssertEqual(h.startMinute, 0)
        XCTAssertEqual(h.endMinute, 24 * 60)
    }

    // MARK: isWorkingDay / workingRange

    func testStandardIsMondayThroughFridayNineToFive() {
        let h = WorkingHours.standard
        // 2026-09-21 is a Monday.
        for offset in 0..<5 {
            XCTAssertTrue(h.isWorkingDay(cal.date(byAdding: .day, value: offset, to: day(2026, 9, 21))!))
        }
        XCTAssertFalse(h.isWorkingDay(day(2026, 9, 26)))   // Saturday
        XCTAssertFalse(h.isWorkingDay(day(2026, 9, 27)))   // Sunday
        XCTAssertEqual(h.workingRange(on: day(2026, 9, 21)), 540..<1020)
        XCTAssertNil(h.workingRange(on: day(2026, 9, 26)))
    }

    // MARK: nonWorkingRanges (drives the grid shading)

    func testNonWorkingRangesOnAWorkingDayShadesBeforeAndAfter() {
        let h = WorkingHours.standard
        XCTAssertEqual(h.nonWorkingRanges(on: day(2026, 9, 21)), [0..<540, 1020..<1440])
    }

    func testNonWorkingRangesOnAWeekendShadesTheWholeDay() {
        let h = WorkingHours.standard
        XCTAssertEqual(h.nonWorkingRanges(on: day(2026, 9, 26)), [0..<1440])
    }

    func testNonWorkingRangesWhenWorkingDaySpansTheFullDay() {
        let h = WorkingHours(days: [2], startMinute: 0, endMinute: 1440)
        XCTAssertEqual(h.nonWorkingRanges(on: day(2026, 9, 21)), [])
    }

    // MARK: contains

    func testContainsRespectsBothDayAndHour() {
        let h = WorkingHours.standard
        let mondayTen = cal.date(bySettingHour: 10, minute: 0, second: 0, of: day(2026, 9, 21))!
        let mondayEight = cal.date(bySettingHour: 8, minute: 0, second: 0, of: day(2026, 9, 21))!
        let saturdayTen = cal.date(bySettingHour: 10, minute: 0, second: 0, of: day(2026, 9, 26))!
        XCTAssertTrue(h.contains(mondayTen))
        XCTAssertFalse(h.contains(mondayEight))
        XCTAssertFalse(h.contains(saturdayTen))
    }

    // MARK: startHour / scroll position

    func testStartHourMatchesConfiguredStart() {
        XCTAssertEqual(WorkingHours.standard.startHour, 9)
        XCTAssertEqual(WorkingHours(days: [2], startMinute: 7 * 60 + 30, endMinute: 16 * 60).startHour, 7)
    }
}
