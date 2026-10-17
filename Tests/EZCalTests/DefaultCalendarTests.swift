import XCTest
@testable import EZCal

final class DefaultCalendarTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.timeZone = TimeZone(identifier: "UTC")!
        return c
    }()
    private let writable: Set<String> = ["work", "home", "other"]

    /// 2026-10-12 is a Monday.
    private func at(_ day: Int, _ h: Int, _ m: Int = 0) -> Date {
        cal.date(from: DateComponents(year: 2026, month: 10, day: day, hour: h, minute: m))!
    }
    private let mon = 12, fri = 16, sat = 17, sun = 18

    private func schedule() -> DefaultCalendarSettings {
        var s = DefaultCalendarSettings()
        s.mode = .schedule
        s.rules = [
            DefaultCalendarRule(days: [2, 3, 4, 5, 6], startMinute: 9 * 60, endMinute: 17 * 60, sourceId: "work"),
            DefaultCalendarRule(days: [2, 3, 4, 5, 6], startMinute: 17 * 60, endMinute: 9 * 60, sourceId: "home"),
            DefaultCalendarRule(days: [1, 7], startMinute: 0, endMinute: 0, sourceId: "other"),
        ]
        s.fallbackSourceId = "home"
        return s
    }
    private func resolve(_ s: DefaultCalendarSettings, _ d: Date, last: String? = nil) -> String? {
        DefaultCalendarResolver.resolve(s, writable: writable, lastSelected: last, now: d, cal: cal)
    }

    func testFollowSidebarUsesLastSelected() {
        XCTAssertEqual(resolve(DefaultCalendarSettings(), at(mon, 10), last: "home"), "home")
    }
    func testFollowSidebarNilWhenNothingOrStale() {
        XCTAssertNil(resolve(DefaultCalendarSettings(), at(mon, 10)))
        XCTAssertNil(resolve(DefaultCalendarSettings(), at(mon, 10), last: "gone"))
    }
    func testFixed() {
        var s = DefaultCalendarSettings(); s.mode = .fixed; s.fixedSourceId = "work"
        XCTAssertEqual(resolve(s, at(mon, 3), last: "home"), "work")
        s.fixedSourceId = "readonly"
        XCTAssertNil(resolve(s, at(mon, 3)))
    }
    func testScheduleBoundaries() {
        let s = schedule()
        XCTAssertEqual(resolve(s, at(mon, 8, 59)), "home")
        XCTAssertEqual(resolve(s, at(mon, 9)), "work")      // start inclusive
        XCTAssertEqual(resolve(s, at(mon, 16, 59)), "work")
        XCTAssertEqual(resolve(s, at(mon, 17)), "home")     // end exclusive
    }
    func testOvernightSpansIntoNextMorning() {
        let s = schedule()
        XCTAssertEqual(resolve(s, at(mon, 23)), "home")
        XCTAssertEqual(resolve(s, at(mon + 1, 2)), "home")  // Tue 02:00 via Monday's rule
        // Friday night carries into Saturday early morning, which the weekend rule would otherwise claim.
        XCTAssertEqual(resolve(s, at(sat, 2)), "home")
        XCTAssertEqual(resolve(s, at(sat, 9)), "other")
    }
    func testWeekend() {
        let s = schedule()
        XCTAssertEqual(resolve(s, at(sat, 12)), "other")
        XCTAssertEqual(resolve(s, at(sun, 12)), "other")
        // Sunday 02:00 is not covered by Saturday-night (Saturday is not a listed day of the overnight rule).
        XCTAssertEqual(resolve(s, at(sun, 2)), "other")
        // Monday 02:00 follows Sunday, which is not in the overnight rule's days -> weekend rule doesn't match either -> fallback.
        XCTAssertEqual(resolve(s, at(mon, 2)), "home")
    }
    func testFallbackAndUnusableRuleSkipped() {
        var s = schedule()
        s.rules = [DefaultCalendarRule(days: [2], startMinute: 0, endMinute: 0, sourceId: "deleted")]
        s.fallbackSourceId = "other"
        XCTAssertEqual(resolve(s, at(mon, 10)), "other")
        XCTAssertEqual(resolve(s, at(fri, 10)), "other")
        s.fallbackSourceId = nil
        XCTAssertNil(resolve(s, at(mon, 10)))
    }
    func testCodableRoundTripAndGarbage() {
        let s = schedule()
        XCTAssertEqual(DefaultCalendarSettings(rawValue: s.rawValue), s)
        XCTAssertEqual(DefaultCalendarSettings(rawValue: "not json"), DefaultCalendarSettings())
        XCTAssertEqual(DefaultCalendarSettings().mode, .followSidebar)
    }
}
