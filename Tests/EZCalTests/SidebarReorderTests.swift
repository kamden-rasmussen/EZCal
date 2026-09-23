import XCTest
@testable import EZCal

/// `SidebarReorder.rowShift` — the "other rows slide out of the way" math behind the sidebar's live
/// drag-reorder preview (`ReorderableSourceList`).
final class SidebarReorderTests: XCTestCase {
    func testDraggingDownShiftsInterveningRowsUpByOne() {
        // [a b c d e], drag "a" (index 0) down to land at index 3.
        // b, c, d (indices 1...3) should each shift up one row to close the gap "a" left as it passed
        // them; e (index 4, outside the range) and "a" itself shouldn't move.
        XCTAssertEqual(SidebarReorder.rowShift(for: 0, start: 0, target: 3), 0)   // the dragged row itself
        XCTAssertEqual(SidebarReorder.rowShift(for: 1, start: 0, target: 3), -1)
        XCTAssertEqual(SidebarReorder.rowShift(for: 2, start: 0, target: 3), -1)
        XCTAssertEqual(SidebarReorder.rowShift(for: 3, start: 0, target: 3), -1)
        XCTAssertEqual(SidebarReorder.rowShift(for: 4, start: 0, target: 3), 0)
    }

    func testDraggingUpShiftsInterveningRowsDownByOne() {
        // [a b c d e], drag "e" (index 4) up to land at index 1.
        // b, c, d (indices 1...3) should each shift down one row; a (index 0) shouldn't move.
        XCTAssertEqual(SidebarReorder.rowShift(for: 0, start: 4, target: 1), 0)
        XCTAssertEqual(SidebarReorder.rowShift(for: 1, start: 4, target: 1), 1)
        XCTAssertEqual(SidebarReorder.rowShift(for: 2, start: 4, target: 1), 1)
        XCTAssertEqual(SidebarReorder.rowShift(for: 3, start: 4, target: 1), 1)
        XCTAssertEqual(SidebarReorder.rowShift(for: 4, start: 4, target: 1), 0)   // the dragged row itself
    }

    func testDraggingBackToStartIsANoOpForEveryRow() {
        for i in 0..<5 { XCTAssertEqual(SidebarReorder.rowShift(for: i, start: 2, target: 2), 0) }
    }

    func testAdjacentSwapShiftsOnlyTheOneRowBetween() {
        // Dragging index 2 to index 3 only displaces the single row at 3 (up by one); nothing further out moves.
        XCTAssertEqual(SidebarReorder.rowShift(for: 1, start: 2, target: 3), 0)
        XCTAssertEqual(SidebarReorder.rowShift(for: 3, start: 2, target: 3), -1)
        XCTAssertEqual(SidebarReorder.rowShift(for: 4, start: 2, target: 3), 0)
    }
}
