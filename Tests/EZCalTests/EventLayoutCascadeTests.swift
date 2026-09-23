import XCTest
@testable import EZCal

/// Coverage for `EventLayout.waterfallOffset`, the horizontal step `DayColumn` uses to cascade an overlap
/// cluster that's too narrow for side-by-side columns. Replaces the old "one full-width front card, everything
/// else collapsed onto a single shared offset" design (which read as one card with a barely-visible peek behind
/// it, and separately could push a card's frame past the day column's own right edge — the "narnia" bug) with a
/// uniform waterfall: every layer gets the same step, so each event keeps its own always-visible, always-
/// clickable sliver, however many events pile up or however narrow the column is.
final class EventLayoutCascadeTests: XCTestCase {
    /// The property the design actually guarantees: however many events overlap, no two of them ever land on
    /// the same offset — every layer stays visually and click-wise distinct.
    func testEveryLayerInAClusterGetsADistinctOffset() {
        for count in 1...12 {
            let offsets = (0..<count).map { EventLayout.waterfallOffset(index: $0, count: count, dayWidth: 400) }
            XCTAssertEqual(Set(offsets).count, count,
                            "cluster of \(count) overlapping events produced a duplicate offset: \(offsets)")
        }
    }

    /// A lone event (no overlap) never gets shifted.
    func testSingleEventHasNoOffset() {
        XCTAssertEqual(EventLayout.waterfallOffset(index: 0, count: 1, dayWidth: 400), 0)
    }

    /// The earliest-starting event (index 0) sits at the column's natural left edge, unshifted.
    func testEarliestEventHasNoOffset() {
        XCTAssertEqual(EventLayout.waterfallOffset(index: 0, count: 5, dayWidth: 400), 0)
    }

    /// With plenty of width, every layer gets the full ideal step.
    func testGenerousWidthUsesTheIdealStep() {
        let offsets = (0..<4).map { EventLayout.waterfallOffset(index: $0, count: 4, dayWidth: 2000) }
        XCTAssertEqual(offsets, [0, EventLayout.cascadeStep, EventLayout.cascadeStep * 2, EventLayout.cascadeStep * 3])
    }

    /// However narrow the column or however many events pile up, the last (topmost, fully visible) card's
    /// resulting width — `dayWidth - 4 - offset` — never drops below `cascadeMinCardWidth`, so it's never
    /// pushed past the column's own right edge (the original "narnia" bug: an unbounded offset could put a
    /// card's frame outside its own day column entirely).
    func testFrontCardWidthNeverDropsBelowTheMinimumHoweverManyEventsOverlap() {
        let widths: [CGFloat] = [40, 80, 120, 300]
        for count in [2, 3, 6, 12, 20] {
            for dayWidth in widths {
                let lastOffset = EventLayout.waterfallOffset(index: count - 1, count: count, dayWidth: dayWidth)
                let width = dayWidth - 4 - lastOffset
                XCTAssertGreaterThanOrEqual(width, EventLayout.cascadeMinCardWidth - 0.001,
                                             "count=\(count) dayWidth=\(dayWidth) produced width \(width)")
            }
        }
    }

    /// A narrow column (e.g. a week view's day column) still gives a small overlap cluster a real, visible
    /// step rather than collapsing everyone onto the same spot — the regression this design specifically fixes.
    func testNarrowColumnStillGivesEachLayerAVisibleStep() {
        let offset = EventLayout.waterfallOffset(index: 1, count: 2, dayWidth: 108)
        XCTAssertGreaterThan(offset, 8, "a 2-way overlap in a ~108pt week column should still get a readable step")
    }
}
