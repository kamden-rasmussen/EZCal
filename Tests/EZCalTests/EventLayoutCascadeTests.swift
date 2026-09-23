import XCTest
@testable import EZCal

/// Regression coverage for the "items behind are completely invisible" bug: `DayColumn` cascades
/// overlapping full-width event cards by an offset per layer (`EventLayout.cascadeOffset`), and a fixed
/// 3-layer cap used to give a 4th+ overlapping event the exact same offset as the 3rd — landing it on an
/// identical rect, 100% covered and unclickable, not just visually cramped.
final class EventLayoutCascadeTests: XCTestCase {
    /// The property the fix actually guarantees: however many events overlap, no two of them ever land
    /// on the same offset. This is what a screen can't show but a test can check directly.
    func testEveryLayerInAClusterGetsADistinctOffset() {
        for columns in 1...12 {
            let offsets = (0..<columns).map { behind in
                let (x, y) = EventLayout.cascadeOffset(behind: behind, columns: columns)
                return "\(x),\(y)"
            }
            XCTAssertEqual(Set(offsets).count, columns,
                            "cluster of \(columns) overlapping events produced a duplicate offset: \(offsets)")
        }
    }

    /// Reproduces the exact bug as it shipped: with the old `min(behind, 3)` cap, a cluster of 6 collapsed
    /// layers 0–2 onto one identical offset. Asserting the new behavior differs pins the regression.
    func testSixWayOverlapNoLongerCollapsesBehindTheThirdLayer() {
        let offsets = (0..<6).map { EventLayout.cascadeOffset(behind: $0, columns: 6) }
        XCTAssertNotEqual(offsets[0].x, offsets[2].x)
        XCTAssertNotEqual(offsets[0].y, offsets[2].y)
        XCTAssertNotEqual(offsets[1].x, offsets[2].x)
        XCTAssertNotEqual(offsets[1].y, offsets[2].y)
    }

    /// The common case (≤4 overlapping) keeps the original, more generous 10pt/18pt step.
    func testCommonCaseStepUnchanged() {
        let offset = EventLayout.cascadeOffset(behind: 2, columns: 4)
        XCTAssertEqual(offset.x, 20)
        XCTAssertEqual(offset.y, 36)
    }

    /// The front-most card (nothing behind it) always sits at its natural position, unshifted.
    func testFrontCardHasNoOffset() {
        let offset = EventLayout.cascadeOffset(behind: 0, columns: 6)
        XCTAssertEqual(offset.x, 0)
        XCTAssertEqual(offset.y, 0)
    }
}
