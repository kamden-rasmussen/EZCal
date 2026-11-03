import XCTest

final class AgendaNavigationUITests: EZCalUITestCase {

    /// Saturday events in demo data are day 5 of the week; we just need a day with events, so use Today.
    func testAgendaShowsEventsAndDetailSheet() throws {
        let row = app.buttons.matching(identifier: "agendaRow").firstMatch
        XCTAssertTrue(row.waitForExistence(timeout: 10))
        openAgendaRow(row)
        let title = app.staticTexts["detailTitle"]
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
        let buttons = app.buttons.matching(identifier: "joinButton")
        XCTAssertTrue(buttons.firstMatch.waitForExistence(timeout: 10))
        // Which meetings are on screen depends on the weekday; a button under the floating bar can't be
        // tapped, so scroll until the last one sits clear of it.
        let clear = 200.0...700.0
        let list = app.collectionViews["agendaList"]
        for _ in 0..<4 where !buttons.allElementsBoundByIndex.contains(where: { clear.contains($0.frame.midY) }) {
            list.swipeUp()
        }
        let join = buttons.allElementsBoundByIndex.last(where: { clear.contains($0.frame.midY) })!
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

    func testMenuGoToDateFromAgenda() throws {
        openMenuItem("goToDateMenuButton", expecting: "goToDatePicker")
        XCTAssertTrue(anyEl("goToDatePicker").waitForExistence(timeout: 5))
        app.buttons["goToTodayButton"].tap()
        XCTAssertTrue(anyEl("goToDatePicker").waitForNonExistence(timeout: 5))
    }

    // MARK: - Jump to date (#109)

    func testTapTitleOpensDatePickerAndJumps() throws {
        selectTab("Day")
        XCTAssertTrue(dayTitle.waitForExistence(timeout: 5))
        let before = dayTitle.label
        dayTitle.tap()
        XCTAssertTrue(anyEl("goToDatePicker").waitForExistence(timeout: 5))
        // Pick tomorrow in the month grid (its accessibility label is the full date).
        let cal = Calendar.current
        var tomorrow = cal.date(byAdding: .day, value: 1, to: Date())!
        if !cal.isDate(tomorrow, equalTo: Date(), toGranularity: .month) { tomorrow = cal.date(byAdding: .day, value: -1, to: Date())! }
        let label = tomorrow.formatted(.dateTime.weekday(.wide).month(.wide).day())
        let target = app.buttons.matching(NSPredicate(format: "label CONTAINS %@", label)).firstMatch
        XCTAssertTrue(target.waitForExistence(timeout: 5), "no day button '\(label)'")
        target.tap()
        XCTAssertTrue(anyEl("goToDatePicker").waitForNonExistence(timeout: 5))
        XCTAssertNotEqual(dayTitle.label, before)
        app.buttons["todayButton"].tap()
        XCTAssertEqual(dayTitle.label, before)
    }

    // MARK: - Swipe paging (#106)

    func testSwipeChangesDayAndVerticalSwipeDoesNot() throws {
        selectTab("Day")
        XCTAssertTrue(dayTitle.waitForExistence(timeout: 5))
        let today = dayTitle.label
        let grid = app.scrollViews.firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        grid.swipeUp()
        XCTAssertEqual(dayTitle.label, today, "vertical scroll must not change the day")
        grid.swipeLeft()
        XCTAssertNotEqual(dayTitle.label, today, "swipe left goes to the next day")
        grid.swipeRight()
        XCTAssertEqual(dayTitle.label, today, "swipe right goes back")
        grid.swipeRight()
        XCTAssertNotEqual(dayTitle.label, today)
    }

    func testSwipeChangesWeek() throws {
        selectTab("Day")
        pickGrid("Week")
        XCTAssertTrue(dayTitle.waitForExistence(timeout: 5))
        let before = dayTitle.label
        app.scrollViews.firstMatch.swipeLeft()
        XCTAssertNotEqual(dayTitle.label, before)
        app.scrollViews.firstMatch.swipeRight()
        XCTAssertEqual(dayTitle.label, before)
    }

    // MARK: - Polish (#137)

    func testAgendaLastCardScrollsAboveFloatingBar() throws {
        let list = app.collectionViews["agendaList"]
        XCTAssertTrue(list.waitForExistence(timeout: 10))
        for _ in 0..<10 { list.swipeUp(velocity: .fast) }
        let rows = app.buttons.matching(identifier: "agendaRow")
        let last = rows.element(boundBy: rows.count - 1)
        XCTAssertLessThanOrEqual(last.frame.maxY, app.buttons["todayButton"].frame.minY + 1, "last agenda row hidden behind bar")
    }

    func testSettingsSheetShowsAccountStatus() throws {
        openMenuItem("settingsButton", expecting: "settingsDoneButton")
        XCTAssertTrue(app.staticTexts["Zoom"].waitForExistence(timeout: 5))
        let n = app.descendants(matching: .any).matching(NSPredicate(format: "label CONTAINS 'Not set up on iOS yet'")).count
        XCTAssertGreaterThanOrEqual(n, 1)
        // The Google section sits lower in the sheet; scroll until its sign-in button exists.
        let google = app.descendants(matching: .any).matching(identifier: "googleSignInButton").firstMatch
        for _ in 0..<8 where !google.exists { app.swipeUp() }
        XCTAssertTrue(google.exists)
        for _ in 0..<8 where !app.buttons["settingsDoneButton"].isHittable { app.swipeDown() }
        app.buttons["settingsDoneButton"].tap()
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

    func testSearchFindsEventsAndOpensDetail() throws {
        let field = app.textFields["agendaSearch"]
        XCTAssertTrue(field.waitForExistence(timeout: 10))
        field.tap(); field.typeText("roadmap")
        let result = app.buttons.matching(identifier: "searchResult").firstMatch
        XCTAssertTrue(result.waitForExistence(timeout: 5))
        XCTAssertTrue(result.label.contains("Roadmap planning"))
        // Guest names are searched too.
        field.clearAndType("Marcus Lee")
        XCTAssertTrue(app.buttons.matching(NSPredicate(format: "label CONTAINS 'Design review'")).firstMatch.waitForExistence(timeout: 5))
        field.clearAndType("zzzznomatch")
        XCTAssertTrue(app.staticTexts["No Results for “zzzznomatch”"].waitForExistence(timeout: 5))
        field.clearAndType("roadmap")
        app.buttons.matching(identifier: "searchResult").firstMatch.tap()
        XCTAssertTrue(app.staticTexts["detailTitle"].waitForExistence(timeout: 5))
        XCTAssertEqual(app.staticTexts["detailTitle"].label, "Roadmap planning")
    }

    // MARK: - Current-time indicator (#108)

    func testNowLineOnTodayOnly() throws {
        selectTab("Day")
        XCTAssertTrue(revealNowLine(), "today should show the now line")
        app.buttons["nextButton"].tap()
        XCTAssertTrue(anyEl("nowLine").waitForNonExistence(timeout: 5), "other days must not")
        app.buttons["todayButton"].tap()
        pickGrid("Week")
        XCTAssertTrue(revealNowLine(), "week containing today shows it too")
    }
}
