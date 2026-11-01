import XCTest

final class MonthDetailUITests: EZCalUITestCase {

    func testMonthShowsTodaySelectedAndEvents() throws {
        openMonth()
        XCTAssertTrue(anyEl(cellID(Date())).exists, "today cell missing")
        XCTAssertTrue(anyEl("monthSelectedHeader").exists)
        // Demo data is week-relative, so some day this month near today has events; tap through the week.
        var found = false
        for off in 0..<7 {
            let d = Calendar.current.date(byAdding: .day, value: off, to: Date())!
            guard Calendar.current.isDate(d, equalTo: Date(), toGranularity: .month) else { continue }
            anyEl(cellID(d)).tap()
            if app.buttons["monthRow"].firstMatch.waitForExistence(timeout: 1) { found = true; break }
        }
        XCTAssertTrue(found, "no day with events in month list")
        app.buttons["monthRow"].firstMatch.tap()
        XCTAssertTrue(app.staticTexts["detailTitle"].waitForExistence(timeout: 5))
        app.buttons["doneButton"].tap()
    }

    func testMonthStepAndOpenDay() throws {
        openMonth()
        // Step/today arithmetic is covered by NavigationTests; this checks the Month-to-Day hand-off.
        // Select a day then open it in Day view; anchor must carry over.
        let d = Calendar.current.date(byAdding: .day, value: Calendar.current.component(.day, from: Date()) == 1 ? 1 : -1, to: Date())!
        if Calendar.current.isDate(d, equalTo: Date(), toGranularity: .month) { anyEl(cellID(d)).tap() }
        let header = anyEl("monthSelectedHeader").label
        app.buttons["openDayButton"].tap()
        XCTAssertTrue(anyEl("dayGridBackground").waitForExistence(timeout: 5))
        XCTAssertFalse(anyEl("monthGrid").exists)
        XCTAssertFalse(header.isEmpty)
        // Back to Month and to Agenda keeps working.
        pickGrid("Month")
        XCTAssertTrue(anyEl("monthGrid").waitForExistence(timeout: 5))
        selectTab("Agenda")
        XCTAssertTrue(app.collectionViews["agendaList"].waitForExistence(timeout: 5))
    }

    func testMonthEmptyDay() throws {
        openMonth()
        for _ in 0..<2 { app.buttons["nextButton"].tap() }
        XCTAssertTrue(anyEl("monthEmpty").waitForExistence(timeout: 5))
        app.buttons["todayButton"].tap()
    }

    func testDetailLocationRowIsMapsButton() throws {
        app.buttons["addButton"].tap()
        let field = anyEl("editorTitle")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap(); field.typeText("UITest Place")
        let loc = anyEl("editorLocation")
        loc.tap(); loc.typeText("1 Infinite Loop")
        app.buttons["editorSave"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5))
        app.buttons.matching(NSPredicate(format: "label CONTAINS 'UITest Place'")).firstMatch.tap()
        let row = app.buttons["locationButton"]
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(row.label.contains("1 Infinite Loop"))
        // Tapping would leave the app for Maps; the URL builder is what we can check without that.
    }

    func testDetailShowsAttendeesWithRSVPState() throws {
        app.terminate()
        app.launchEnvironment["EZCAL_TEST_OPEN_EVENT"] = "Design review"
        app.launch()
        XCTAssertTrue(app.staticTexts["detailTitle"].waitForExistence(timeout: 10))
        let row = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Marcus Lee, maybe'")).firstMatch
        // Lazy list in a sheet: the first swipe may only grow the detent, so wait after each one.
        for _ in 0..<6 where !row.waitForExistence(timeout: 1) { app.staticTexts["detailTitle"].swipeUp() }
        XCTAssertTrue(row.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Dana Cole, declined'")).firstMatch.waitForExistence(timeout: 5))
        XCTAssertTrue(app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Sam Ortiz, no response'")).firstMatch.waitForExistence(timeout: 5))
    }

    /// The detail list is lazy: swipe until the element is realised and hittable.
    private func scrollDetail(to el: XCUIElement) -> XCUIElement {
        for _ in 0..<6 where !(el.exists && el.isHittable) { app.staticTexts["detailTitle"].swipeUp() }
        XCTAssertTrue(el.isHittable)
        return el
    }

    private func openDesignReview() {
        app.terminate()
        app.launchEnvironment["EZCAL_TEST_OPEN_EVENT"] = "Design review"
        app.launch()
        XCTAssertTrue(app.staticTexts["detailTitle"].waitForExistence(timeout: 10))
    }

    func testRSVPUpdatesOwnResponse() throws {
        openDesignReview()
        let maybe = scrollDetail(to: app.buttons["Maybe"])
        maybe.tap()
        let me = app.descendants(matching: .any).matching(NSPredicate(format: "label BEGINSWITH 'Me, maybe'")).firstMatch
        for _ in 0..<6 where !me.exists { maybe.swipeDown() }
        if !me.waitForExistence(timeout: 5) {
            let labels = app.descendants(matching: .any).matching(identifier: "attendeeRow").allElementsBoundByIndex.map(\.label)
            XCTFail("own row should show the new response; rows: \(labels); done=\(app.buttons["doneButton"].exists)")
        }
        XCTAssertTrue(app.buttons["doneButton"].exists, "sheet stays open")
    }

    func testAddGuestFromDirectorySuggestion() throws {
        openDesignReview()
        let field = scrollDetail(to: anyEl("addGuestField"))
        field.tap()
        field.typeText("alex")
        let suggestion = app.buttons["guestSuggestion"].firstMatch
        XCTAssertTrue(suggestion.waitForExistence(timeout: 5))
        suggestion.tap()
        let added = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Alex Rivera, no response'")).firstMatch
        XCTAssertTrue(added.waitForExistence(timeout: 5))
    }

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
}
