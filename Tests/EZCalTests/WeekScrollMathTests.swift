import XCTest
@testable import EZCal

final class WeekScrollMathTests: XCTestCase {
    private var cal: Calendar = {
        var c = Calendar(identifier: .gregorian)
        c.locale = Locale(identifier: "en_US")
        c.timeZone = TimeZone(identifier: "America/Denver")!
        return c
    }()
    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date { cal.date(from: DateComponents(year: y, month: m, day: d))! }
    private func weekday(_ d: Date) -> Int { cal.component(.weekday, from: d) }   // 1 Sun ... 7 Sat

    // MARK: work-week day skipping

    func testMonFriRuleSkipsWeekends() {
        let fri = day(2026, 9, 25)
        XCTAssertEqual(WeekScrollMath.shift(fri, byColumns: 1, rule: .monFri, cal: cal), day(2026, 9, 28))   // Fri -> Mon
        XCTAssertEqual(WeekScrollMath.shift(day(2026, 9, 28), byColumns: -1, rule: .monFri, cal: cal), fri)  // Mon -> Fri
        XCTAssertEqual(WeekScrollMath.shift(fri, byColumns: 5, rule: .monFri, cal: cal), day(2026, 10, 2))   // exactly one week
        XCTAssertEqual(WeekScrollMath.shift(fri, byColumns: -10, rule: .monFri, cal: cal), day(2026, 9, 11))
    }

    func testFirstColumnDayRollsWeekendForward() {
        XCTAssertEqual(WeekScrollMath.firstColumnDay(onOrAfter: day(2026, 9, 26), rule: .monFri, cal: cal), day(2026, 9, 28))
        XCTAssertEqual(WeekScrollMath.firstColumnDay(onOrAfter: day(2026, 9, 27), rule: .monFri, cal: cal), day(2026, 9, 28))
        XCTAssertEqual(WeekScrollMath.firstColumnDay(onOrAfter: day(2026, 9, 23), rule: .monFri, cal: cal), day(2026, 9, 23))
        XCTAssertEqual(WeekScrollMath.firstColumnDay(onOrAfter: day(2026, 9, 26), rule: .all, cal: cal), day(2026, 9, 26))
    }

    func testColumnDaysFromMidweekWrapPastTheWeekend() {
        let days = WeekScrollMath.columnDays(from: day(2026, 9, 23), count: 5, rule: .monFri, cal: cal)   // Wed
        XCTAssertEqual(days, [day(2026, 9, 23), day(2026, 9, 24), day(2026, 9, 25), day(2026, 9, 28), day(2026, 9, 29)])
        let week = WeekScrollMath.columnDays(from: day(2026, 9, 23), count: 7, rule: .all, cal: cal)
        XCTAssertEqual(week.count, 7)
        XCTAssertEqual(week.last, day(2026, 9, 29))
        let noWeekends = WeekScrollMath.columnDays(from: day(2026, 9, 25), count: 3, rule: .localeWeekdays, cal: cal)
        XCTAssertEqual(noWeekends, [day(2026, 9, 25), day(2026, 9, 28), day(2026, 9, 29)])
    }

    // MARK: window

    func testWindowIsContiguousAndCentered() {
        let center = day(2026, 9, 21)
        let w = WeekScrollMath.window(around: center, before: 14, after: 21, rule: .all, cal: cal)
        XCTAssertEqual(w.count, 14 + 21 + 1)
        XCTAssertEqual(w[14], center)
        XCTAssertEqual(w.first, day(2026, 9, 7))
        XCTAssertEqual(w.last, day(2026, 10, 12))
    }

    func testWorkWeekWindowHasNoWeekendsAndCentersOnAWeekday() {
        let w = WeekScrollMath.window(around: day(2026, 9, 26), before: 10, after: 10, rule: .monFri, cal: cal)   // Sat -> Mon
        XCTAssertEqual(w.count, 21)
        XCTAssertEqual(w[10], day(2026, 9, 28))
        XCTAssertTrue(w.allSatisfy { (2...6).contains(weekday($0)) })
        XCTAssertEqual(Set(w).count, w.count)
    }

    func testExtendsOnlyNearAnEnd() {
        let w = WeekScrollMath.window(around: day(2026, 9, 21), before: 100, after: 100, rule: .all, cal: cal)
        XCTAssertNil(WeekScrollMath.extended(w, leadingIndex: 100, visibleCount: 7, thresholdColumns: 28, chunk: 182, rule: .all, cal: cal))

        let near = WeekScrollMath.extended(w, leadingIndex: 10, visibleCount: 7, thresholdColumns: 28, chunk: 182, rule: .all, cal: cal)
        XCTAssertEqual(near?.prepended, 182)
        XCTAssertEqual(near?.days.count, w.count + 182)
        XCTAssertEqual(near?.days[182], w[0])   // old first column keeps its place after the new front

        let far = WeekScrollMath.extended(w, leadingIndex: w.count - 8, visibleCount: 7, thresholdColumns: 28, chunk: 182, rule: .all, cal: cal)
        XCTAssertEqual(far?.prepended, 0)
        XCTAssertEqual(far?.days.count, w.count + 182)
        XCTAssertEqual(far?.days[w.count], cal.date(byAdding: .day, value: 1, to: w.last!).map { cal.startOfDay(for: $0) })
    }

    func testExtensionStaysContiguousAcrossWeekendsForWorkWeek() {
        let w = WeekScrollMath.window(around: day(2026, 9, 21), before: 10, after: 10, rule: .monFri, cal: cal)
        let ext = WeekScrollMath.extended(w, leadingIndex: 0, visibleCount: 5, thresholdColumns: 5, chunk: 15, rule: .monFri, cal: cal)!
        XCTAssertTrue(ext.days.allSatisfy { (2...6).contains(weekday($0)) })
        XCTAssertEqual(ext.days, ext.days.sorted())
        XCTAssertEqual(Set(ext.days).count, ext.days.count)
    }

    // MARK: offset -> leading day

    func testLeadingIndexRoundsToNearestColumn() {
        XCTAssertEqual(WeekScrollMath.leadingIndex(offset: 0, colWidth: 100, count: 50), 0)
        XCTAssertEqual(WeekScrollMath.leadingIndex(offset: 49, colWidth: 100, count: 50), 0)
        XCTAssertEqual(WeekScrollMath.leadingIndex(offset: 51, colWidth: 100, count: 50), 1)
        XCTAssertEqual(WeekScrollMath.leadingIndex(offset: 1234, colWidth: 100, count: 50), 12)
        XCTAssertEqual(WeekScrollMath.leadingIndex(offset: -300, colWidth: 100, count: 50), 0)      // rubber band
        XCTAssertEqual(WeekScrollMath.leadingIndex(offset: 99_999, colWidth: 100, count: 50), 49)
        XCTAssertEqual(WeekScrollMath.leadingIndex(offset: 10, colWidth: 0, count: 50), 0)
    }

    func testVisibleIndicesCoverViewportPlusOverscan() {
        // 5 columns of 100 across a 500pt viewport, scrolled half a column in.
        XCTAssertEqual(WeekScrollMath.visibleIndices(offset: 1250, colWidth: 100, viewport: 500, count: 100, overscan: 1), 11...18)
        XCTAssertEqual(WeekScrollMath.visibleIndices(offset: 0, colWidth: 100, viewport: 500, count: 100, overscan: 1), 0...5)
        XCTAssertEqual(WeekScrollMath.visibleIndices(offset: 9_900, colWidth: 100, viewport: 500, count: 100, overscan: 1)?.upperBound, 99)
        XCTAssertNil(WeekScrollMath.visibleIndices(offset: 0, colWidth: 100, viewport: 500, count: 0, overscan: 1))
    }

    // MARK: fetching

    func testFetchRangeBuffersVisibleDays() {
        let days = WeekScrollMath.columnDays(from: day(2026, 9, 21), count: 5, rule: .monFri, cal: cal)
        let r = WeekScrollMath.fetchRange(visible: days, bufferDays: 14, cal: cal)
        XCTAssertEqual(r.lowerBound, day(2026, 9, 7))
        XCTAssertEqual(r.upperBound, day(2026, 10, 10))   // end of Fri Sep 25 (= Sat 26) + 14
    }

    func testNeedsReloadOnlyNearTheLoadedEdges() {
        let week: TimeInterval = 7 * 86_400
        let loaded = day(2026, 9, 1)..<day(2026, 10, 31)
        XCTAssertFalse(WeekScrollMath.needsReload(visible: day(2026, 9, 21)..<day(2026, 9, 26), loaded: loaded, margin: week))
        XCTAssertTrue(WeekScrollMath.needsReload(visible: day(2026, 9, 3)..<day(2026, 9, 8), loaded: loaded, margin: week))
        XCTAssertTrue(WeekScrollMath.needsReload(visible: day(2026, 10, 27)..<day(2026, 11, 1), loaded: loaded, margin: week))
        XCTAssertTrue(WeekScrollMath.needsReload(visible: day(2026, 9, 21)..<day(2026, 9, 26), loaded: nil, margin: week))
    }

    func testShouldAnimateShortHopsOnly() {
        XCTAssertTrue(WeekScrollMath.shouldAnimate(columns: 7))
        XCTAssertTrue(WeekScrollMath.shouldAnimate(columns: -21))
        XCTAssertFalse(WeekScrollMath.shouldAnimate(columns: 22))
    }

    func testHeaderColumnGeometryMatchesGridAtRestAndMidPan() {
        let colW: CGFloat = 137.5
        // At rest on column 12: its header sits at x = 0; the next one exactly one column over.
        XCTAssertEqual(WeekScrollMath.columnX(index: 12, colWidth: colW, offset: 12 * colW), 0)
        XCTAssertEqual(WeekScrollMath.columnX(index: 13, colWidth: colW, offset: 12 * colW), colW)
        // Mid-pan (40% of a column): everything shifted by exactly the pan distance.
        let off = 12 * colW + 0.4 * colW
        XCTAssertEqual(WeekScrollMath.columnX(index: 12, colWidth: colW, offset: off), -0.4 * colW, accuracy: 0.0001)
        // The leading column is still the nearest one until the halfway point.
        XCTAssertEqual(WeekScrollMath.leadingIndex(offset: off, colWidth: colW, count: 400), 12)
        XCTAssertEqual(WeekScrollMath.leadingIndex(offset: 12 * colW + 0.6 * colW, colWidth: colW, count: 400), 13)
    }
}
