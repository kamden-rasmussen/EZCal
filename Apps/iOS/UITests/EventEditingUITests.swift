import XCTest

final class EventEditingUITests: EZCalUITestCase {

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
        scrollEditor(to: "editorDelete")
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
        scrollEditor(to: "editorDelete")
        XCTAssertTrue(app.buttons["editorDelete"].waitForExistence(timeout: 5))
        app.buttons["editorDelete"].tap()
        let all = app.buttons["Delete all events"]
        XCTAssertTrue(all.waitForExistence(timeout: 5), "delete scope dialog missing")
        all.tap()
        XCTAssertTrue(row.waitForNonExistence(timeout: 5))
    }

    func testAddAlertToNewEventAndPersist() throws {
        selectTab("Day")
        app.buttons["nextButton"].tap()
        app.buttons["addButton"].tap()
        let field = anyEl("editorTitle")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("UITest Alerts")
        scrollEditor(to: "editorAddAlert")
        XCTAssertTrue(anyEl("editorAlertsDefault").waitForExistence(timeout: 5))
        anyEl("editorAddAlert").tap()
        XCTAssertTrue(anyEl("editorAlert-0").waitForExistence(timeout: 5))
        app.buttons["editorSave"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'UITest Alerts'")).firstMatch.tap()
        app.buttons["editButton"].tap()
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        scrollEditor(to: "editorAddAlert")
        let alert = anyEl("editorAlert-0")
        XCTAssertTrue(alert.waitForExistence(timeout: 5), "saved alert missing after reopening")
        XCTAssertTrue(alert.label.contains("10 minutes"), "alert label was \(alert.label)")
        app.buttons["editorCancel"].tap()
    }

    func testDetailDuplicateAndDelete() throws {
        createEvent(titled: "UITest Detail")
        let row = app.buttons.matching(NSPredicate(format: "label CONTAINS 'UITest Detail'")).firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        row.tap()

        // Duplicate opens the editor prefilled with the same title.
        revealInDetail("duplicateButton").tap()
        let target = app.buttons["Team"]
        XCTAssertTrue(target.waitForExistence(timeout: 5))
        target.tap()
        let field = anyEl("editorTitle")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        XCTAssertEqual(field.value as? String, "UITest Detail")
        app.buttons["editorSave"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        // The copy has the same title and time on another calendar, so the Agenda stacks both into one row (#140).
        // Check this event's own row: on Sundays the demo's three-calendar "Team planning" is stacked as well.
        let stackedRow = app.buttons.matching(identifier: "agendaRow")
            .matching(NSPredicate(format: "label CONTAINS 'UITest Detail' AND label CONTAINS 'On 2 calendars'")).firstMatch
        XCTAssertTrue(stackedRow.waitForExistence(timeout: 5), "duplicate should stack with the original")

        // Delete both copies from the detail sheet.
        for _ in 0..<2 {
            app.buttons.matching(NSPredicate(format: "label CONTAINS 'UITest Detail'")).firstMatch.tap()
            // While both copies exist the row opens the calendar picker first; afterwards it opens the detail directly.
            if anyEl("stackCalendarsHeader").waitForExistence(timeout: 2) {
                app.buttons.matching(NSPredicate(format: "label CONTAINS 'open event'")).firstMatch.tap()
            }
            revealInDetail("detailDelete").tap()
            let confirm = app.buttons["Delete"]
            XCTAssertTrue(confirm.waitForExistence(timeout: 5))
            confirm.tap()
            XCTAssertTrue(app.staticTexts["detailTitle"].waitForNonExistence(timeout: 5))
        }
        XCTAssertTrue(app.staticTexts["UITest Detail"].waitForNonExistence(timeout: 5), "events should be gone")
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
}
