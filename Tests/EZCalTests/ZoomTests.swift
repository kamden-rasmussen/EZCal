import XCTest
@testable import EZCal

/// Zoom's real API can't be exercised in this environment (no credentials), so these tests cover the
/// pure, non-networked pieces: the request-body construction for `ZoomAPI.createMeeting` and the
/// marker/block formatting in `ZoomNotes`.
final class ZoomTests: XCTestCase {
    private let start = Date(timeIntervalSince1970: 1_800_000_000)
    private var end: Date { start.addingTimeInterval(1800) }

    private func options(waitingRoom: Bool = true, muteOnEntry: Bool = false, joinBeforeHost: Bool = false,
                          hostVideoOn: Bool = true, participantVideoOn: Bool = false, passcodeEnabled: Bool = true) -> ZoomMeetingOptions {
        ZoomMeetingOptions(waitingRoom: waitingRoom, muteOnEntry: muteOnEntry, joinBeforeHost: joinBeforeHost,
                           hostVideoOn: hostVideoOn, participantVideoOn: participantVideoOn, passcodeEnabled: passcodeEnabled)
    }

    // MARK: - Create Meeting payload

    func testCreateMeetingBodyIncludesTimingAndTopic() {
        let body = ZoomAPI.createMeetingBody(topic: "Design review", start: start, end: end, agenda: "", options: options())
        XCTAssertEqual(body["topic"] as? String, "Design review")
        XCTAssertEqual(body["type"] as? Int, 2)
        XCTAssertEqual(body["duration"] as? Int, 30)
        XCTAssertEqual(body["start_time"] as? String, RFC3339.string(start))
        XCTAssertEqual(body["timezone"] as? String, TimeZone.current.identifier)
    }

    func testCreateMeetingBodyOmitsAgendaWhenEmptyAndTruncatesWhenLong() {
        let empty = ZoomAPI.createMeetingBody(topic: "t", start: start, end: end, agenda: "", options: options())
        XCTAssertNil(empty["agenda"])

        let longAgenda = String(repeating: "x", count: 5000)
        let withAgenda = ZoomAPI.createMeetingBody(topic: "t", start: start, end: end, agenda: longAgenda, options: options())
        XCTAssertEqual((withAgenda["agenda"] as? String)?.count, 1900)
    }

    func testCreateMeetingBodySettingsMatchOptions() throws {
        let o = options(waitingRoom: false, muteOnEntry: true, joinBeforeHost: true, hostVideoOn: false, participantVideoOn: true)
        let body = ZoomAPI.createMeetingBody(topic: "t", start: start, end: end, agenda: "", options: o)
        let settings = try XCTUnwrap(body["settings"] as? [String: Any])
        XCTAssertEqual(settings["waiting_room"] as? Bool, false)
        XCTAssertEqual(settings["mute_upon_entry"] as? Bool, true)
        XCTAssertEqual(settings["join_before_host"] as? Bool, true)
        XCTAssertEqual(settings["host_video"] as? Bool, false)
        XCTAssertEqual(settings["participant_video"] as? Bool, true)
    }

    func testCreateMeetingBodyDisablesPasscodeWithEmptyPassword() {
        let body = ZoomAPI.createMeetingBody(topic: "t", start: start, end: end, agenda: "", options: options(passcodeEnabled: false))
        XCTAssertEqual(body["password"] as? String, "")
    }

    func testCreateMeetingBodyOmitsPasswordWhenPasscodeEnabled() {
        let body = ZoomAPI.createMeetingBody(topic: "t", start: start, end: end, agenda: "", options: options(passcodeEnabled: true))
        XCTAssertNil(body["password"])
    }

    func testCreateMeetingBodyDurationIsAtLeastOneMinute() {
        let body = ZoomAPI.createMeetingBody(topic: "t", start: start, end: start, agenda: "", options: options())
        XCTAssertEqual(body["duration"] as? Int, 1)
    }

    // MARK: - Notes block

    private func meeting(password: String? = "abc123") -> ZoomMeeting {
        ZoomMeeting(id: 987_654_3210 % Int.max, joinURL: "https://acme.zoom.us/j/5551234", password: password)
    }

    func testBlockPlainText() {
        let block = ZoomNotes.block(for: meeting(), html: false)
        XCTAssertTrue(block.contains("Join Zoom Meeting"))
        XCTAssertTrue(block.contains("https://acme.zoom.us/j/5551234"))
        XCTAssertTrue(block.contains("Meeting ID:"))
        XCTAssertTrue(block.contains("Passcode: abc123"))
    }

    func testBlockOmitsPasscodeLineWhenNoPassword() {
        let block = ZoomNotes.block(for: meeting(password: nil), html: false)
        XCTAssertFalse(block.contains("Passcode"))
    }

    func testBlockHTMLWrapsLinkInAnchor() {
        let block = ZoomNotes.block(for: meeting(), html: true)
        XCTAssertTrue(block.contains("<a href=\"https://acme.zoom.us/j/5551234\">"))
        XCTAssertTrue(block.contains("<br>"))
    }

    func testAppendingToEmptyNotesReturnsBlockAlone() {
        XCTAssertEqual(ZoomNotes.appending("BLOCK", to: "", html: false), "BLOCK")
    }

    func testAppendingToExistingNotesAddsSeparator() {
        XCTAssertEqual(ZoomNotes.appending("BLOCK", to: "Existing notes", html: false), "Existing notes\n\nBLOCK")
        XCTAssertEqual(ZoomNotes.appending("BLOCK", to: "Existing notes", html: true), "Existing notes<br><br>BLOCK")
    }

    // MARK: - Remove Zoom link

    func testRemovingZoomBlockStripsLinesAndCollapsesBlanks() {
        let notes = "Standup notes\n\nJoin Zoom Meeting\nhttps://acme.zoom.us/j/5551234\n\nMeeting ID: 5551234\nPasscode: abc123"
        XCTAssertEqual(ZoomNotes.removingZoomBlock(from: notes), "Standup notes")
    }

    func testRemovingZoomBlockKeepsUnrelatedText() {
        let notes = "Agenda:\n- item one\n- item two\n\nJoin Zoom Meeting\nhttps://acme.zoom.us/j/1\n\nMeeting ID: 1"
        XCTAssertEqual(ZoomNotes.removingZoomBlock(from: notes), "Agenda:\n- item one\n- item two")
    }

    func testRemovingZoomBlockIsIdempotentWhenNoBlockPresent() {
        XCTAssertEqual(ZoomNotes.removingZoomBlock(from: "Just some notes."), "Just some notes.")
        XCTAssertEqual(ZoomNotes.removingZoomBlock(from: ""), "")
    }

    // MARK: - Hidden marker (EventKit meeting-id remembrance)

    func testMarkerRoundTrip() {
        let withMarker = ZoomNotes.applyingMarker(id: "123456789", to: "Join Zoom Meeting\nhttps://acme.zoom.us/j/1")
        XCTAssertEqual(ZoomNotes.meetingID(in: withMarker), "123456789")
    }

    func testMarkerIsInvisibleInStrippedNotes() {
        let notes = "Some notes"
        let withMarker = ZoomNotes.applyingMarker(id: "42", to: notes)
        XCTAssertNotEqual(withMarker, notes) // marker was appended...
        XCTAssertEqual(ZoomNotes.strippingMarker(withMarker), notes) // ...but strips back to the original
    }

    func testMeetingIDIsNilWhenNoMarkerPresent() {
        XCTAssertNil(ZoomNotes.meetingID(in: "Notes with no zoom marker at all."))
    }

    func testApplyingMarkerReplacesAnExistingOne() {
        let first = ZoomNotes.applyingMarker(id: "111", to: "Notes")
        let second = ZoomNotes.applyingMarker(id: "222", to: first)
        XCTAssertEqual(ZoomNotes.meetingID(in: second), "222")
        // Only one marker should remain.
        XCTAssertEqual(ZoomNotes.strippingMarker(second), "Notes")
    }

    func testApplyingNilMarkerRemovesExistingOne() {
        let withMarker = ZoomNotes.applyingMarker(id: "42", to: "Notes")
        let removed = ZoomNotes.applyingMarker(id: nil, to: withMarker)
        XCTAssertNil(ZoomNotes.meetingID(in: removed))
        XCTAssertEqual(removed, "Notes")
    }

    func testApplyingMarkerToEmptyNotesReturnsJustTheMarker() {
        let result = ZoomNotes.applyingMarker(id: "7", to: "")
        XCTAssertEqual(ZoomNotes.meetingID(in: result), "7")
        XCTAssertEqual(ZoomNotes.strippingMarker(result), "")
    }

    // MARK: - ZoomMeetingOptions defaults follow AppSettings

    func testDefaultsReflectAppSettingsKeys() {
        let d = UserDefaults.standard
        let originals = ["zoomWaitingRoom", "zoomMuteOnEntry"].map { ($0, d.object(forKey: $0)) }
        defer { for (k, v) in originals { if let v { d.set(v, forKey: k) } else { d.removeObject(forKey: k) } } }

        d.set(false, forKey: "zoomWaitingRoom")
        d.set(true, forKey: "zoomMuteOnEntry")
        let opts = ZoomMeetingOptions.defaults
        XCTAssertFalse(opts.waitingRoom)
        XCTAssertTrue(opts.muteOnEntry)
    }
}
