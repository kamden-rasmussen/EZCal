import XCTest
import EventKit
@testable import EZCal

/// Issue #3: edit/delete scope for recurring events. These are pure mapping/logic tests — no
/// EKEventStore or network calls, per the issue's "unit tests for the span/scope mapping logic".
final class RecurrenceTests: XCTestCase {

    // MARK: EKSpan mapping

    func testEKSpanMapping() {
        XCTAssertEqual(RecurrenceScope.thisEvent.ekSpan, .thisEvent)
        XCTAssertEqual(RecurrenceScope.thisAndFollowing.ekSpan, .futureEvents)
        XCTAssertEqual(RecurrenceScope.all.ekSpan, .futureEvents)
    }

    // MARK: Google delete target

    func testGoogleDeleteTargetThisEventUsesInstanceId() {
        let target = RecurrenceScope.googleDeleteTarget(scope: .thisEvent, eventId: "inst123", recurringEventId: "series1")
        XCTAssertEqual(target, .instance(eventId: "inst123"))
    }

    func testGoogleDeleteTargetAllUsesRecurringEventId() {
        let target = RecurrenceScope.googleDeleteTarget(scope: .all, eventId: "inst123", recurringEventId: "series1")
        XCTAssertEqual(target, .series(eventId: "series1"))
    }

    func testGoogleDeleteTargetAllFallsBackToOwnIdWhenNoParent() {
        // A master event fetched directly (not an expanded instance) has no recurringEventId of its own.
        let target = RecurrenceScope.googleDeleteTarget(scope: .all, eventId: "series1", recurringEventId: nil)
        XCTAssertEqual(target, .series(eventId: "series1"))
    }

    func testGoogleDeleteTargetThisAndFollowingTruncatesSeries() {
        let target = RecurrenceScope.googleDeleteTarget(scope: .thisAndFollowing, eventId: "inst123", recurringEventId: "series1")
        XCTAssertEqual(target, .truncateSeries(masterEventId: "series1"))
    }

    // MARK: Google patch (edit) target

    func testGooglePatchTargetThisEventUsesInstanceId() {
        let target = RecurrenceScope.googlePatchTarget(scope: .thisEvent, eventId: "inst123", recurringEventId: "series1")
        XCTAssertEqual(target, .instance(eventId: "inst123"))
    }

    func testGooglePatchTargetAllUsesSeriesId() {
        let target = RecurrenceScope.googlePatchTarget(scope: .all, eventId: "inst123", recurringEventId: "series1")
        XCTAssertEqual(target, .series(eventId: "series1"))
    }

    func testGooglePatchTargetThisAndFollowingSplitsSeries() {
        let target = RecurrenceScope.googlePatchTarget(scope: .thisAndFollowing, eventId: "inst123", recurringEventId: "series1")
        XCTAssertEqual(target, .splitSeries(masterEventId: "series1"))
    }

    // MARK: RRULE truncation

    func testTruncatedAddsUntil() {
        let cutoff = Date(timeIntervalSince1970: 1_800_000_000)   // 2027-01-15T08:00:00Z
        let result = RecurrenceRule.truncated(["RRULE:FREQ=WEEKLY;BYDAY=MO"], before: cutoff)
        XCTAssertEqual(result.count, 1)
        XCTAssertTrue(result[0].hasPrefix("RRULE:FREQ=WEEKLY;BYDAY=MO;UNTIL="), result[0])
        // UNTIL must be strictly before the cutoff instant, not equal to it.
        XCTAssertTrue(result[0].hasSuffix("Z"))
    }

    func testTruncatedReplacesExistingUntilAndDropsCount() {
        let cutoff = Date(timeIntervalSince1970: 1_800_000_000)
        let result = RecurrenceRule.truncated(["RRULE:FREQ=DAILY;COUNT=50;UNTIL=20991231T000000Z"], before: cutoff)
        XCTAssertEqual(result.count, 1)
        XCTAssertFalse(result[0].contains("COUNT="))
        XCTAssertEqual(result[0].components(separatedBy: "UNTIL=").count, 2)   // exactly one UNTIL
    }

    func testTruncatedLeavesNonRRuleLinesAlone() {
        let cutoff = Date(timeIntervalSince1970: 1_800_000_000)
        let result = RecurrenceRule.truncated(["RRULE:FREQ=DAILY", "EXDATE:20260101T090000Z"], before: cutoff)
        XCTAssertEqual(result[1], "EXDATE:20260101T090000Z")
    }

    func testTruncatedUntilFormatIsUTCBasic() {
        let cutoff = Date(timeIntervalSince1970: 1_800_000_000)
        let result = RecurrenceRule.truncated(["RRULE:FREQ=DAILY"], before: cutoff)
        let until = result[0].components(separatedBy: "UNTIL=")[1]
        // yyyyMMdd'T'HHmmss'Z'
        XCTAssertEqual(until.count, 16)
        XCTAssertTrue(until.contains("T"))
        XCTAssertTrue(until.hasSuffix("Z"))
    }

    // MARK: Recurrence options (create-time picker)

    func testRecurrenceOptionRRules() {
        XCTAssertNil(RecurrenceOption.none.rrule)
        XCTAssertEqual(RecurrenceOption.daily.rrule, "RRULE:FREQ=DAILY")
        XCTAssertEqual(RecurrenceOption.weekly.rrule, "RRULE:FREQ=WEEKLY")
        XCTAssertEqual(RecurrenceOption.monthly.rrule, "RRULE:FREQ=MONTHLY")
        XCTAssertEqual(RecurrenceOption.weekdays.rrule, "RRULE:FREQ=WEEKLY;BYDAY=MO,TU,WE,TH,FR")
    }

    func testRecurrenceOptionEKRule() {
        XCTAssertNil(RecurrenceOption.none.ekRule)
        XCTAssertEqual(RecurrenceOption.daily.ekRule?.frequency, .daily)
        XCTAssertEqual(RecurrenceOption.weekly.ekRule?.frequency, .weekly)
        XCTAssertEqual(RecurrenceOption.monthly.ekRule?.frequency, .monthly)
        let weekdays = RecurrenceOption.weekdays.ekRule
        XCTAssertEqual(weekdays?.frequency, .weekly)
        XCTAssertEqual(weekdays?.daysOfTheWeek?.count, 5)
    }

    // MARK: Sheet identity / misc

    func testRecurrenceActionNoun() {
        XCTAssertEqual(RecurrenceAction.edit.noun, "Edit")
        XCTAssertEqual(RecurrenceAction.delete.noun, "Delete")
    }

    func testActiveSheetIdsDifferByEventAndAction() {
        let e = CalEvent(id: "x1", eventId: "x1", sourceId: "s", calendarId: "c", accountId: "a", uid: "x1",
                         title: "T", start: Date(), end: Date().addingTimeInterval(60), isAllDay: false,
                         location: "", notes: "", attendees: [], htmlLink: nil, meetingURL: nil, colorHex: "#fff",
                         sourceName: "", ownerName: nil, isOverlay: false, canEdit: true, isBusyOnly: false,
                         isRecurring: true, zoomMeetingID: nil, isTentative: false, isDeclined: false)
        let editSheet = ActiveSheet.recurrenceScope(e, .edit)
        let deleteSheet = ActiveSheet.recurrenceScope(e, .delete)
        XCTAssertNotEqual(editSheet.id, deleteSheet.id)
    }
}
