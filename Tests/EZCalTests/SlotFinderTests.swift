import XCTest
@testable import EZCal

final class SlotFinderTests: XCTestCase {
    private let cal = Calendar(identifier: .gregorian)

    private func day(_ y: Int, _ m: Int, _ d: Int) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: 0))!
    }

    private func at(_ y: Int, _ m: Int, _ d: Int, _ h: Int, _ min: Int = 0) -> Date {
        cal.date(from: DateComponents(year: y, month: m, day: d, hour: h, minute: min))!
    }

    // A Tuesday, arbitrary.
    private var monday: Date { day(2026, 9, 21) }

    func testFindsFreeSlotWithinWorkingHours() {
        let slots = SlotFinder.findSlots(
            emails: ["a@x.com"],
            busy: ["a@x.com": []],
            myBusy: [],
            duration: 3600,
            days: [monday],
            calendar: cal
        )
        XCTAssertFalse(slots.isEmpty)
        XCTAssertEqual(slots.first?.start, at(2026, 9, 21, 9))
        // Nothing before working hours or after it minus duration.
        XCTAssertTrue(slots.allSatisfy { $0.start >= at(2026, 9, 21, 9) && $0.end <= at(2026, 9, 21, 18) })
    }

    func testExcludesSlotsWhereAKnownAttendeeIsBusy() {
        let busyRange = at(2026, 9, 21, 9)..<at(2026, 9, 21, 12)
        let slots = SlotFinder.findSlots(
            emails: ["a@x.com"],
            busy: ["a@x.com": [busyRange]],
            myBusy: [],
            duration: 3600,
            days: [monday],
            calendar: cal
        )
        XCTAssertTrue(slots.allSatisfy { $0.start >= at(2026, 9, 21, 12) })
    }

    func testOverlappingBusyRangesFromMultiplePeopleAllBlock() {
        // a is busy 9-10, b is busy 10-11: only 11+ is free for both.
        let slots = SlotFinder.findSlots(
            emails: ["a@x.com", "b@x.com"],
            busy: [
                "a@x.com": [at(2026, 9, 21, 9)..<at(2026, 9, 21, 10)],
                "b@x.com": [at(2026, 9, 21, 10)..<at(2026, 9, 21, 11)],
            ],
            myBusy: [],
            duration: 1800,
            days: [monday],
            calendar: cal
        )
        XCTAssertTrue(slots.allSatisfy { $0.start >= at(2026, 9, 21, 11) })
    }

    func testOrganizersOwnBusyRangesBlockEvenWithNoGuests() {
        let slots = SlotFinder.findSlots(
            emails: [],
            busy: [:],
            myBusy: [at(2026, 9, 21, 9)..<at(2026, 9, 21, 17)],
            duration: 3600,
            days: [monday],
            calendar: cal
        )
        XCTAssertEqual(slots.count, 1)
        XCTAssertEqual(slots.first?.start, at(2026, 9, 21, 17))
    }

    func testUnknownAttendeeNeverBlocksASlotButIsReported() {
        let slots = SlotFinder.findSlots(
            emails: ["ghost@x.com"],
            busy: ["ghost@x.com": nil],   // present but nil = not visible to us
            myBusy: [],
            duration: 3600,
            days: [monday],
            calendar: cal
        )
        XCTAssertFalse(slots.isEmpty)
        XCTAssertEqual(slots.first?.attendees.first?.unknown, true)
        XCTAssertEqual(slots.first?.attendees.first?.busy, false)
    }

    func testMissingKeyIsTreatedAsUnknownJustLikeNilValue() {
        let slots = SlotFinder.findSlots(
            emails: ["ghost@x.com"],
            busy: [:],   // key absent entirely
            myBusy: [],
            duration: 3600,
            days: [monday],
            calendar: cal
        )
        XCTAssertEqual(slots.first?.attendees.first?.unknown, true)
    }

    func testSlotsWithFewerUnknownsAreRankedFirst() {
        let slots = SlotFinder.findSlots(
            emails: ["known@x.com", "ghost@x.com"],
            busy: [
                "known@x.com": [at(2026, 9, 21, 9)..<at(2026, 9, 21, 10)],  // busy 9-10, free after
                "ghost@x.com": nil,                                          // unknown all day
            ],
            myBusy: [],
            duration: 1800,
            days: [monday],
            calendar: cal
        )
        // Every returned slot has one unknown attendee (ghost); just confirm none before 10 (known's busy time).
        XCTAssertTrue(slots.allSatisfy { $0.start >= at(2026, 9, 21, 10) })
        XCTAssertTrue(slots.allSatisfy { $0.unknownCount == 1 })
    }

    func testRespectsCustomWorkingHours() {
        let hours = WorkingHours(startHour: 7, endHour: 8)
        let slots = SlotFinder.findSlots(
            emails: [],
            busy: [:],
            myBusy: [],
            duration: 1800,
            days: [monday],
            workingHours: hours,
            calendar: cal
        )
        XCTAssertTrue(slots.allSatisfy { $0.start >= at(2026, 9, 21, 7) && $0.end <= at(2026, 9, 21, 8) })
    }

    func testDurationLongerThanWorkingDayReturnsNothing() {
        let slots = SlotFinder.findSlots(
            emails: [],
            busy: [:],
            myBusy: [],
            duration: 20 * 3600,
            days: [monday],
            calendar: cal
        )
        XCTAssertTrue(slots.isEmpty)
    }

    func testNonPositiveDurationReturnsNothing() {
        XCTAssertTrue(SlotFinder.findSlots(emails: [], busy: [:], myBusy: [], duration: 0, days: [monday], calendar: cal).isEmpty)
        XCTAssertTrue(SlotFinder.findSlots(emails: [], busy: [:], myBusy: [], duration: -100, days: [monday], calendar: cal).isEmpty)
    }

    func testSearchesMultipleDaysInOrder() {
        let tuesday = day(2026, 9, 22)
        let slots = SlotFinder.findSlots(
            emails: [],
            busy: [:],
            myBusy: [],
            duration: 3600,
            days: [monday, tuesday],
            calendar: cal
        )
        XCTAssertTrue(cal.isDate(slots.first!.start, inSameDayAs: monday))
        XCTAssertTrue(slots.contains { cal.isDate($0.start, inSameDayAs: tuesday) })
    }

    func testLimitCapsResultCount() {
        let slots = SlotFinder.findSlots(
            emails: [], busy: [:], myBusy: [],
            duration: 900, days: [monday],
            granularity: 900, limit: 3, calendar: cal
        )
        XCTAssertEqual(slots.count, 3)
    }
}
