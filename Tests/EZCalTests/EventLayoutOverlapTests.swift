import XCTest
@testable import EZCal

/// Coverage for the hybrid side-by-side/cascade overlap layout: `EventLayout.place`'s side-by-side slot
/// packing, `EventLayout.useSideBySide`'s width/mode decision, and `EventLayout.clusters(of:)` regrouping a
/// flat placement list back into per-cluster arrays for `OverlapCluster`.
final class EventLayoutOverlapTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func event(_ id: String, _ start: Date, minutes: Int, source: String = "s") -> CalEvent {
        CalEvent(id: id, eventId: id, sourceId: source, calendarId: source, accountId: "a", uid: id, title: id,
                 start: start, end: start.addingTimeInterval(Double(minutes) * 60), isAllDay: false,
                 location: "", notes: "", attendees: [], htmlLink: nil, meetingURL: nil, colorHex: "#fff",
                 sourceName: source, ownerName: nil, isOverlay: false, canEdit: true, isBusyOnly: false,
                 isRecurring: false, zoomMeetingID: nil, isTentative: false, isDeclined: false)
    }

    private var day: Date { cal.date(from: DateComponents(year: 2026, month: 3, day: 2))! }
    private var nine: Date { cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)! }

    // MARK: - side-by-side packing

    func testNonOverlappingEventsEachGetTheirOwnSlot() {
        // b starts after a ends, but both share a's cluster because c bridges them — packing should still
        // reuse a's now-free slot for b rather than opening a needless third column.
        let placed = EventLayout.place([
            event("a", nine, minutes: 30),                             // 9:00–9:30
            event("b", nine.addingTimeInterval(45 * 60), minutes: 30), // 9:45–10:15, doesn't overlap a
            event("c", nine.addingTimeInterval(15 * 60), minutes: 60), // 9:15–10:15, overlaps both
        ], day: day, cal: cal)
        let byId = Dictionary(uniqueKeysWithValues: placed.map { ($0.id, $0) })
        XCTAssertEqual(byId["a"]!.sideSlots, 2)
        XCTAssertEqual(byId["b"]!.sideSlots, 2)
        XCTAssertEqual(byId["c"]!.sideSlots, 2)
        XCTAssertEqual(byId["a"]!.sideSlot, byId["b"]!.sideSlot, "a's slot should be freed and reused by b")
        XCTAssertNotEqual(byId["a"]!.sideSlot, byId["c"]!.sideSlot)
    }

    func testAllMutuallyOverlappingEventsGetDistinctSlots() {
        let placed = EventLayout.place([
            event("a", nine, minutes: 60),
            event("b", nine, minutes: 60),
            event("c", nine, minutes: 60),
        ], day: day, cal: cal)
        XCTAssertEqual(Set(placed.map(\.sideSlot)).count, 3)
        for p in placed { XCTAssertEqual(p.sideSlots, 3) }
    }

    func testSingleEventGetsOneSlot() {
        let placed = EventLayout.place([event("a", nine, minutes: 30)], day: day, cal: cal)
        XCTAssertEqual(placed[0].sideSlot, 0)
        XCTAssertEqual(placed[0].sideSlots, 1)
    }

    // MARK: - useSideBySide

    func testCascadeModeNeverUsesSideBySideRegardlessOfWidth() {
        XCTAssertFalse(EventLayout.useSideBySide(sideSlots: 2, availableWidth: 2000, mode: .cascade))
    }

    func testAutoModeUsesSideBySideWhenSlicesStayReadable() {
        XCTAssertTrue(EventLayout.useSideBySide(sideSlots: 2, availableWidth: 400, mode: .auto))
    }

    func testAutoModeFallsBackToCascadeWhenSlicesWouldBeTooNarrow() {
        XCTAssertFalse(EventLayout.useSideBySide(sideSlots: 5, availableWidth: 120, mode: .auto))
    }

    func testAutoModeNeverSlicesASingleUnclusteredEvent() {
        XCTAssertFalse(EventLayout.useSideBySide(sideSlots: 1, availableWidth: 2000, mode: .auto))
    }

    // MARK: - clusters(of:)

    func testClustersGroupsByOverlapAndPreservesOrder() {
        let placed = EventLayout.place([
            event("a", nine, minutes: 30),
            event("b", nine.addingTimeInterval(10 * 60), minutes: 30),   // overlaps a
            event("c", nine.addingTimeInterval(4 * 3600), minutes: 30),  // alone, separate cluster
        ], day: day, cal: cal)
        let clusters = EventLayout.clusters(of: placed)
        XCTAssertEqual(clusters.count, 2)
        XCTAssertEqual(Set(clusters[0].map(\.id)), Set(["a", "b"]))
        XCTAssertEqual(clusters[1].map(\.id), ["c"])
    }
}
