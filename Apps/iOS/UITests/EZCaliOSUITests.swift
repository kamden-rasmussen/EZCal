import XCTest

final class EZCaliOSUITests: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["EZCAL_DEMO"] = "1"
        app.launch()
    }

    private var picker: XCUIElement { app.segmentedControls["tabPicker"] }
    private func selectTab(_ name: String) {
        let b = picker.buttons[name]
        XCTAssertTrue(b.waitForExistence(timeout: 10))
        b.tap()
    }
    private func anyEl(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    private var dayTitle: XCUIElement { app.staticTexts["dayTitle"] }

    /// Saturday events in demo data are day 5 of the week; we just need a day with events, so use Today.
    func testAgendaShowsEventsAndDetailSheet() throws {
        let row = app.buttons.matching(identifier: "agendaRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        row.tap()
        let title = app.staticTexts["detailTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 5))
        app.buttons["doneButton"].tap()
        XCTAssertTrue(title.waitForNonExistence(timeout: 5))
        XCTAssertTrue(row.exists)
    }

    func testTabSwitchAndNavigation() throws {
        selectTab("Day")
        XCTAssertTrue(dayTitle.waitForExistence(timeout: 5))
        let today = dayTitle.label
        app.buttons["nextButton"].tap()
        XCTAssertNotEqual(dayTitle.label, today)
        app.buttons["prevButton"].tap()
        XCTAssertEqual(dayTitle.label, today)
        app.buttons["prevButton"].tap()
        let prev = dayTitle.label
        XCTAssertNotEqual(prev, today)
        app.buttons["todayButton"].tap()
        XCTAssertEqual(dayTitle.label, today)
        selectTab("Agenda")
        XCTAssertTrue(app.otherElements["agendaList"].exists || app.collectionViews["agendaList"].exists)
    }

    func testAgendaNextChangesContent() throws {
        let list = app.collectionViews["agendaList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        let before = list.staticTexts.firstMatch.label
        for _ in 0..<2 { app.buttons["nextButton"].tap() }
        // Agenda starts at the anchor, so the first section header moves.
        XCTAssertNotEqual(list.staticTexts.firstMatch.label, before)
        app.buttons["todayButton"].tap()
        XCTAssertEqual(list.staticTexts.firstMatch.label, before)
    }

    func testDayEventBlockOpensDetail() throws {
        selectTab("Day")
        // Move forward until a timed event block is visible (demo data is week-relative).
        var found = false
        for _ in 0..<7 {
            if anyEl("dayEvent").waitForExistence(timeout: 1) { found = true; break }
            app.buttons["nextButton"].tap()
        }
        XCTAssertTrue(found, "no timed events in the next week")
        anyEl("dayEvent").tap()
        XCTAssertTrue(app.staticTexts["detailTitle"].waitForExistence(timeout: 5))
        app.buttons["doneButton"].tap()
        XCTAssertTrue(app.staticTexts["detailTitle"].waitForNonExistence(timeout: 5))
    }

    func testEmptyDayInDayView() throws {
        selectTab("Day")
        // Demo data spans -1...+1 weeks; 30 days out is guaranteed empty.
        for _ in 0..<30 { app.buttons["nextButton"].tap() }
        XCTAssertTrue(dayTitle.exists)
        XCTAssertFalse(anyEl("dayEvent").exists)
        XCTAssertFalse(anyEl("allDayEvent").exists)
        app.buttons["todayButton"].tap()
    }

    func testDayScrollEndsWithLastHourVisible() throws {
        selectTab("Day")
        let grid = app.scrollViews.firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        for _ in 0..<6 { grid.swipeUp(velocity: .fast) }
        let hour = anyEl("hour-23")
        XCTAssertTrue(hour.waitForExistence(timeout: 3), "23:00 row missing")
        let bar = app.buttons["todayButton"]
        XCTAssertTrue(bar.exists)
        XCTAssertLessThanOrEqual(hour.frame.maxY, bar.frame.minY, "23:00 row hidden behind bottom bar")
    }

    func testPullToRefreshDoesNotCrash() throws {
        let list = app.collectionViews["agendaList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        let start = list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.15))
        start.press(forDuration: 0.1, thenDragTo: list.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.8)))
        XCTAssertTrue(list.waitForExistence(timeout: 5))
        XCTAssertEqual(app.state, .runningForeground)
        selectTab("Day")
        let grid = app.scrollViews.firstMatch
        grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1))
            .press(forDuration: 0.1, thenDragTo: grid.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.9)))
        XCTAssertEqual(app.state, .runningForeground)
    }

    // MARK: - Create / edit / delete (demo data is in-memory, so these never touch a real account)

    private func replaceText(_ field: XCUIElement, with text: String) {
        field.tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }

    private func createEvent(titled title: String) {
        app.buttons["addButton"].tap()
        let field = anyEl("editorTitle")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(title)
        app.buttons["editorSave"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "editor should close after save")
    }

    func testCreateEditDeleteEvent() throws {
        selectTab("Day")
        XCTAssertTrue(dayTitle.waitForExistence(timeout: 5))
        // Tomorrow: the + button defaults to 9:00 there, independent of the time the test runs.
        app.buttons["nextButton"].tap()
        createEvent(titled: "UITest Created")
        let block = app.buttons.matching(NSPredicate(format: "label CONTAINS 'UITest Created'")).firstMatch
        XCTAssertTrue(block.waitForExistence(timeout: 5), "new event not in Day view")

        selectTab("Agenda")
        XCTAssertTrue(app.staticTexts["UITest Created"].waitForExistence(timeout: 5), "new event not in Agenda")

        // Edit the title.
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'UITest Created'")).firstMatch.tap()
        app.buttons["editButton"].tap()
        let field = anyEl("editorTitle")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        replaceText(field, with: "UITest Renamed")
        app.buttons["editorSave"].tap()
        XCTAssertTrue(app.staticTexts["UITest Renamed"].waitForExistence(timeout: 5))
        XCTAssertFalse(app.staticTexts["UITest Created"].exists)

        // Delete it with confirmation.
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'UITest Renamed'")).firstMatch.tap()
        app.buttons["editButton"].tap()
        XCTAssertTrue(app.buttons["editorDelete"].waitForExistence(timeout: 5))
        app.buttons["editorDelete"].tap()
        let confirm = app.buttons["Delete"]
        XCTAssertTrue(confirm.waitForExistence(timeout: 5))
        confirm.tap()
        XCTAssertTrue(app.staticTexts["UITest Renamed"].waitForNonExistence(timeout: 5), "event should be gone")
    }

    func testRecurringEditAsksScopeAndDeleteScopeRemovesSeries() throws {
        app.buttons["addButton"].tap()
        let field = anyEl("editorTitle")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("UITest Repeating")
        let rep = app.buttons["editorRepeat"]
        rep.tap()
        app.buttons["Daily"].tap()
        app.buttons["editorSave"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'UITest Repeating'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()
        app.buttons["editButton"].tap()
        XCTAssertTrue(app.buttons["This and following events"].waitForExistence(timeout: 5), "scope dialog missing")
        XCTAssertTrue(app.buttons["All events"].exists)
        app.buttons["This event"].tap()
        XCTAssertTrue(app.buttons["editorDelete"].waitForExistence(timeout: 5))
        app.buttons["editorDelete"].tap()
        let all = app.buttons["Delete all events"]
        XCTAssertTrue(all.waitForExistence(timeout: 5), "delete scope dialog missing")
        all.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
    }

    func testLongPressEmptyDayCreatesEventAtTime() throws {
        selectTab("Day")
        for _ in 0..<30 { app.buttons["nextButton"].tap() }   // empty day
        let bg = anyEl("dayGridBackground")
        XCTAssertTrue(bg.waitForExistence(timeout: 5))
        bg.coordinate(withNormalizedOffset: CGVector(dx: 0.6, dy: 0.4)).press(forDuration: 1.0)
        let field = anyEl("editorTitle")
        XCTAssertTrue(field.waitForExistence(timeout: 5), "long press should open the editor")
        app.buttons["editorCancel"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
    }

    // MARK: - Calendar list / settings

    /// Tap the switch knob (trailing edge); a center tap lands on the label and may not toggle.
    private func flip(_ t: XCUIElement) { t.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }

    func testCalendarListTogglesFilterAgenda() throws {
        let rows = app.buttons.matching(identifier: "agendaRow")
        XCTAssertTrue(rows.firstMatch.waitForExistence(timeout: 10))
        let names = ["Me", "Team", "Home", "Family", "City League"]
        let before = rows.count
        app.buttons["menuButton"].tap()
        app.buttons["calendarsButton"].tap()
        for n in names {
            let t = app.switches["calendarToggle-\(n)"]
            XCTAssertTrue(t.waitForExistence(timeout: 5), "missing toggle \(n)")
            flip(t)
        }
        app.buttons["calendarsDoneButton"].tap()
        XCTAssertLessThan(rows.count, before, "hidden calendars should filter Agenda")
        app.buttons["menuButton"].tap()
        app.buttons["calendarsButton"].tap()
        for n in names { flip(app.switches["calendarToggle-\(n)"]) }
        app.buttons["calendarsDoneButton"].tap()
        XCTAssertEqual(rows.count, before)
    }

    func testSettingsSheetShowsAccountStatus() throws {
        app.buttons["menuButton"].tap()
        app.buttons["settingsButton"].tap()
        XCTAssertTrue(app.staticTexts["Google Calendar"].waitForExistence(timeout: 5))
        let n = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Not set up on iOS yet'")).count
        XCTAssertGreaterThanOrEqual(n, 2)
        app.buttons["settingsDoneButton"].tap()
    }

    // MARK: - Touch drag / resize

    /// Goes to Day view and returns the first timed event block found in the coming week.
    private func firstDayEvent() -> XCUIElement {
        selectTab("Day")
        for _ in 0..<7 {
            if anyEl("dayEvent").waitForExistence(timeout: 1) { return anyEl("dayEvent") }
            app.buttons["nextButton"].tap()
        }
        XCTFail("no timed events in the next week")
        return anyEl("dayEvent")
    }

    private func chooseScopeIfAsked() {
        let b = app.buttons["This event"]
        if b.waitForExistence(timeout: 1.5) { b.tap() }
    }

    func testLongPressDragMovesEvent() throws {
        let ev = firstDayEvent()
        let before = ev.value as? String
        // Drag towards the middle of the screen so we never end up under the bars.
        let down = ev.frame.midY < app.frame.midY
        let from = ev.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
        let to = from.withOffset(CGVector(dx: 0, dy: down ? 84 : -84))   // 1.5 h at 56 pt/h
        from.press(forDuration: 0.8, thenDragTo: to)
        chooseScopeIfAsked()
        let moved = anyEl("dayEvent")
        XCTAssertTrue(moved.waitForExistence(timeout: 5))
        XCTAssertNotEqual(moved.value as? String, before, "event time should change after a move")
        XCTAssertFalse(app.staticTexts["detailTitle"].exists, "a drag must not open details")
    }

    func testResizeHandlesChangeEndAndStart() throws {
        let ev = firstDayEvent()
        let before = ev.value as? String ?? ""
        // Lift without moving: selects the block and shows the handles.
        ev.press(forDuration: 0.8)
        let bottom = anyEl("resizeBottom")
        XCTAssertTrue(bottom.waitForExistence(timeout: 5), "handles should show after lifting")
        bottom.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: bottom.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .withOffset(CGVector(dx: 0, dy: 56)))
        chooseScopeIfAsked()
        let afterBottom = anyEl("dayEvent").value as? String ?? ""
        XCTAssertNotEqual(afterBottom, before, "end time should change after resizing the bottom")
        let startBefore = before.components(separatedBy: " – ").first
        XCTAssertEqual(afterBottom.components(separatedBy: " – ").first, startBefore, "bottom resize keeps the start")

        let top = anyEl("resizeTop")
        XCTAssertTrue(top.waitForExistence(timeout: 5))
        top.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
            .press(forDuration: 0.1, thenDragTo: top.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.5))
                .withOffset(CGVector(dx: 0, dy: -28)))
        chooseScopeIfAsked()
        let afterTop = anyEl("dayEvent").value as? String ?? ""
        XCTAssertNotEqual(afterTop.components(separatedBy: " – ").first, startBefore, "top resize should change the start")
        XCTAssertEqual(afterTop.components(separatedBy: " – ").last, afterBottom.components(separatedBy: " – ").last)
    }

    func testTapStillOpensDetailsAfterDragSupport() throws {
        let ev = firstDayEvent()
        ev.tap()
        XCTAssertTrue(app.staticTexts["detailTitle"].waitForExistence(timeout: 5))
    }

    /// Stands in for tapping a meeting notification: the app posts the same `.ezcalOpenEvent` the
    /// notification delegate does (a real notification tap can't be driven from XCUITest).
    func testOpenEventNotificationShowsDetail() throws {
        app.terminate()
        app.launchEnvironment["EZCAL_TEST_OPEN_EVENT"] = "Roadmap planning"
        app.launch()
        let title = app.staticTexts["detailTitle"]
        XCTAssertTrue(title.waitForExistence(timeout: 10))
        XCTAssertEqual(title.label, "Roadmap planning")
    }

    /// A meeting that isn't within 10 minutes of starting asks before joining (macOS parity, #30).
    func testAgendaJoinButtonConfirmsWhenNotYetJoinable() throws {
        XCTAssertTrue(app.buttons.matching(identifier: "joinButton").firstMatch.waitForExistence(timeout: 10))
        let join = app.buttons.matching(identifier: "joinButton").allElementsBoundByIndex.last!
        join.tap()
        let anyway = app.buttons["Join anyway"]
        XCTAssertTrue(anyway.waitForExistence(timeout: 5))
        // On large iPhones the dialog is a popover; tapping outside is its cancel.
        let cancel = app.buttons["Cancel"]
        if cancel.exists { cancel.tap() }
        else { app.otherElements["PopoverDismissRegion"].coordinate(withNormalizedOffset: CGVector(dx: 0.05, dy: 0.95)).tap() }
        XCTAssertTrue(anyway.waitForNonExistence(timeout: 5))
    }

    func testJoinNextMeetingMenuItemAndDayBlockButton() throws {
        app.buttons["menuButton"].tap()
        XCTAssertTrue(anyEl("joinNextButton").waitForExistence(timeout: 5))
        app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.6)).tap()   // dismiss the menu
        selectTab("Day")
        var found = false
        for _ in 0..<7 {
            if app.buttons["joinButton"].waitForExistence(timeout: 1) { found = true; break }
            app.buttons["nextButton"].tap()
        }
        XCTAssertTrue(found, "no video meeting block with a Join button")
    }
}
