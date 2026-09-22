import XCTest
@testable import EZCal

final class ZoneMathTests: XCTestCase {
    private func utc(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        var cal = Calendar(identifier: .gregorian)
        cal.timeZone = TimeZone(identifier: "UTC")!
        return cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // MARK: offsetMinutes / offsetLabel

    func testOffsetMinutesBetweenFixedZones() {
        let ny = TimeZone(identifier: "America/New_York")!   // UTC-5 in January (standard time)
        let berlin = TimeZone(identifier: "Europe/Berlin")!  // UTC+1 in January
        let jan = utc(2026, 1, 15, 12)
        XCTAssertEqual(ZoneMath.offsetMinutes(from: ny, to: berlin, at: jan), 6 * 60)
        XCTAssertEqual(ZoneMath.offsetMinutes(from: berlin, to: ny, at: jan), -6 * 60)
        XCTAssertEqual(ZoneMath.offsetMinutes(from: ny, to: ny, at: jan), 0)
    }

    func testOffsetMinutesAccountsForIndependentDST() {
        // Northern-hemisphere summer: US and EU are both in DST, offset unchanged from winter (6h).
        let ny = TimeZone(identifier: "America/New_York")!
        let berlin = TimeZone(identifier: "Europe/Berlin")!
        let july = utc(2026, 7, 15, 12)
        XCTAssertEqual(ZoneMath.offsetMinutes(from: ny, to: berlin, at: july), 6 * 60)
    }

    func testOffsetLabelFormatting() {
        XCTAssertEqual(ZoneMath.offsetLabel(minutes: 0), "same time")
        XCTAssertEqual(ZoneMath.offsetLabel(minutes: 180), "+3h")
        XCTAssertEqual(ZoneMath.offsetLabel(minutes: -420), "-7h")
        XCTAssertEqual(ZoneMath.offsetLabel(minutes: 330), "+5:30h")
        XCTAssertEqual(ZoneMath.offsetLabel(minutes: -210), "-3:30h")
    }

    func testGMTLabelFormatting() {
        XCTAssertEqual(ZoneMath.gmtLabel(TimeZone(identifier: "UTC")!, at: utc(2026, 1, 1, 0)), "GMT")
        XCTAssertEqual(ZoneMath.gmtLabel(TimeZone(identifier: "Asia/Kolkata")!, at: utc(2026, 1, 1, 0)), "GMT+5:30")
    }

    // MARK: shortName

    func testShortNameForNamedZones() {
        XCTAssertEqual(ZoneMath.shortName(TimeZone(identifier: "America/Los_Angeles")!, at: utc(2026, 1, 1, 0)), "PT")
        XCTAssertEqual(ZoneMath.shortName(TimeZone(identifier: "Europe/Berlin")!, at: utc(2026, 1, 1, 0)), "CET")
        XCTAssertEqual(ZoneMath.shortName(TimeZone(identifier: "Europe/Berlin")!, at: utc(2026, 7, 1, 0)), "CEST")
        XCTAssertEqual(ZoneMath.shortName(TimeZone(identifier: "Asia/Tokyo")!, at: utc(2026, 1, 1, 0)), "JST")
    }

    // MARK: wallClock / dayShift

    func testWallClockConvertsAcrossZones() {
        // 2026-01-15 00:30 UTC is 2026-01-14 19:30 in New York (UTC-5).
        let d = utc(2026, 1, 15, 0, 30)
        let ny = TimeZone(identifier: "America/New_York")!
        let wc = ZoneMath.wallClock(d, in: ny)
        XCTAssertEqual(wc.hour, 19)
        XCTAssertEqual(wc.minute, 30)
    }

    func testDayShiftDetectsPreviousAndNextDay() {
        // 2026-01-15 20:00 UTC: still the 15th in New York (-5h -> 15:00) but already the 16th in Tokyo (+9h -> 05:00).
        let d = utc(2026, 1, 15, 20, 0)
        let utcZone = TimeZone(identifier: "UTC")!
        let ny = TimeZone(identifier: "America/New_York")!
        let tokyo = TimeZone(identifier: "Asia/Tokyo")!
        XCTAssertEqual(ZoneMath.dayShift(of: d, local: utcZone, zone: ny), 0)
        XCTAssertEqual(ZoneMath.dayShift(of: d, local: utcZone, zone: utcZone), 0)
        XCTAssertEqual(ZoneMath.dayShift(of: d, local: utcZone, zone: tokyo), 1)
        XCTAssertEqual(ZoneMath.dayShift(of: d, local: tokyo, zone: ny), -1)
    }

    // MARK: rangeLabel
    // Formatted with the test process's locale, so these check structure (zone suffix, weekday prefix)
    // rather than an exact locale-specific clock string.

    func testRangeLabelOmitsWeekdayOnSameDay() {
        let start = utc(2026, 1, 15, 17, 0)   // noon in New York
        let end = utc(2026, 1, 15, 18, 0)
        let ny = TimeZone(identifier: "America/New_York")!
        let label = ZoneMath.rangeLabel(start: start, end: end, in: ny, local: TimeZone(identifier: "UTC")!)
        XCTAssertTrue(label.hasSuffix(" ET"), label)
        XCTAssertTrue(label.contains("12:00"), label)
        XCTAssertFalse(label.hasPrefix("Wed") || label.hasPrefix("Thu"), label)
    }

    func testRangeLabelIncludesWeekdayWhenDayDiffers() {
        let start = utc(2026, 1, 15, 2, 0)   // 9 PM the prior evening (Wed) in New York
        let end = utc(2026, 1, 15, 3, 0)
        let ny = TimeZone(identifier: "America/New_York")!
        let label = ZoneMath.rangeLabel(start: start, end: end, in: ny, local: TimeZone(identifier: "UTC")!)
        XCTAssertTrue(label.hasPrefix("Wed "), label)
        XCTAssertTrue(label.hasSuffix(" ET"), label)
    }
}
