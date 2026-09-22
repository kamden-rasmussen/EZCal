import XCTest
@testable import EZCal

final class TaskQuickAddTests: XCTestCase {
    func testParsesTitleAndDueDateTime() {
        let r = TaskQuickAdd.parse("task: call dentist tomorrow 3pm")
        XCTAssertEqual(r?.title, "call dentist")
        XCTAssertNotNil(r?.due)
        XCTAssertEqual(r?.hasTime, true)
    }

    func testParsesDateOnlyWithNoTime() {
        let r = TaskQuickAdd.parse("task: pack for trip next friday")
        XCTAssertEqual(r?.title, "pack for trip")
        XCTAssertNotNil(r?.due)
        XCTAssertEqual(r?.hasTime, false)
    }

    func testNoDueDatePhraseLeavesTitleIntact() {
        let r = TaskQuickAdd.parse("task: buy milk")
        XCTAssertEqual(r?.title, "buy milk")
        XCTAssertNil(r?.due)
        XCTAssertEqual(r?.hasTime, false)
    }

    func testEmptyAfterPrefix() {
        let r = TaskQuickAdd.parse("task:")
        XCTAssertEqual(r?.title, "")
        XCTAssertNil(r?.due)
    }

    func testWholeTextIsADatePhrase() {
        // Nothing left for a title after removing the date phrase — keep the raw text rather than lose it.
        let r = TaskQuickAdd.parse("task: tomorrow 3pm")
        XCTAssertEqual(r?.title, "tomorrow 3pm")
        XCTAssertNil(r?.due)
    }

    func testIgnoresTextWithoutTaskPrefix() {
        XCTAssertNil(TaskQuickAdd.parse("call dentist tomorrow"))
        XCTAssertNil(TaskQuickAdd.parse("go to next friday"))
        XCTAssertNil(TaskQuickAdd.parse("new event tomorrow"))
    }

    func testCaseInsensitiveAndWhitespaceTolerantPrefix() {
        XCTAssertNotNil(TaskQuickAdd.parse("TASK: renew license"))
        XCTAssertNotNil(TaskQuickAdd.parse("task:renew license"))
        XCTAssertNotNil(TaskQuickAdd.parse("  task:   renew license  "))
    }

    func testCollapsesWhitespaceLeftBehindByAMidSentenceDate() {
        let r = TaskQuickAdd.parse("task: remind me tomorrow to call mom")
        XCTAssertEqual(r?.title, "remind me to call mom")
    }
}
