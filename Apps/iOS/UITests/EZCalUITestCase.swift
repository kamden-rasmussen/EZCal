import XCTest

/// Shared launch and helpers for the iOS UI test classes. Tests are spread over several classes because Xcode
/// parallelises UI tests per class (`make ios-test`), so one big class would run serially on one simulator.
class EZCalUITestCase: XCTestCase {
    var app: XCUIApplication!

    override func setUpWithError() throws {
        continueAfterFailure = false
        app = XCUIApplication()
        app.launchEnvironment["EZCAL_DEMO"] = "1"
        app.launch()
    }

    var picker: XCUIElement { app.segmentedControls["tabPicker"] }
    func selectTab(_ name: String) {
        let b = picker.buttons[name]
        XCTAssertTrue(b.waitForExistence(timeout: 10))
        b.tap()
    }
    func pickGrid(_ name: String) {
        let p = anyEl("gridModePicker")
        XCTAssertTrue(p.waitForExistence(timeout: 5))
        p.tap()
        app.buttons[name].firstMatch.tap()
    }
    func anyEl(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    var dayTitle: XCUIElement { app.buttons["dayTitle"] }

    // MARK: - Create / edit / delete (demo data is in-memory, so these never touch a real account)

    func replaceText(_ field: XCUIElement, with text: String) {
        field.tap()
        let current = (field.value as? String) ?? ""
        field.typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: current.count) + text)
    }

    /// The editor is a lazy list: scroll until `id` has been realised.
    func scrollEditor(to id: String) {
        let el = id == "editorAddAlert" ? anyEl("editorAddAlert") : anyEl(id)
        for _ in 0..<8 where !el.exists || !el.isHittable {
            // Drag inside the form (above the keyboard) so the keyboard dismisses and the list scrolls.
            app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.45))
                .press(forDuration: 0.05, thenDragTo: app.coordinate(withNormalizedOffset: CGVector(dx: 0.5, dy: 0.1)))
        }
    }

    func createEvent(titled title: String) {
        app.buttons["addButton"].tap()
        let field = anyEl("editorTitle")
        XCTAssertTrue(field.waitForExistence(timeout: 5))
        field.tap()
        field.typeText(title)
        app.buttons["editorSave"].tap()
        XCTAssertTrue(field.waitForNonExistence(timeout: 5), "editor should close after save")
    }

    // MARK: - Calendar list / settings

    /// Tap the switch knob (trailing edge); a center tap lands on the label and may not toggle.
    func flip(_ t: XCUIElement) { t.coordinate(withNormalizedOffset: CGVector(dx: 0.93, dy: 0.5)).tap() }

    // MARK: - Touch drag / resize

    /// Goes to Day view and returns the first timed event block found in the coming week.
    func firstDayEvent() -> XCUIElement {
        selectTab("Day")
        for _ in 0..<7 {
            if anyEl("dayEvent").waitForExistence(timeout: 1) { return anyEl("dayEvent") }
            app.buttons["nextButton"].tap()
        }
        XCTFail("no timed events in the next week")
        return anyEl("dayEvent")
    }

    func chooseScopeIfAsked() {
        let b = app.buttons["This event"]
        if b.waitForExistence(timeout: 1.5) { b.tap() }
    }

    // MARK: - Month

    func openMonth() {
        selectTab("Day")
        pickGrid("Month")
        XCTAssertTrue(anyEl("monthGrid").waitForExistence(timeout: 5))
    }

    func cellID(_ d: Date) -> String {
        let f = DateFormatter(); f.locale = Locale(identifier: "en_US_POSIX"); f.dateFormat = "yyyy-MM-dd"
        return "monthCell-" + f.string(from: d)
    }

    func revealInDetail(_ id: String) -> XCUIElement {
        let el = anyEl(id)
        XCTAssertTrue(el.waitForExistence(timeout: 5), id)
        for _ in 0..<4 where !el.isHittable { app.staticTexts["detailTitle"].swipeUp() }
        return el
    }

    // MARK: - Drag / resize in multi-day grids (#116)

    /// A week-grid event block that is on screen after scrolling the grid to the top.
    func visibleWeekEvent() -> XCUIElement? {
        selectTab("Day")
        pickGrid("Week")
        let grid = app.scrollViews.firstMatch
        XCTAssertTrue(grid.waitForExistence(timeout: 5))
        for _ in 0..<3 { grid.swipeDown(velocity: .fast) }
        // Demo events are week-relative; step through weeks until one is comfortably on screen.
        for _ in 0..<3 {
            let all = app.descendants(matching: .any).matching(identifier: "weekDayEvent").allElementsBoundByIndex
            if let ev = all.first(where: { $0.isHittable && $0.frame.minY > 330 && $0.frame.maxY < 700 && $0.frame.height > 25 }) { return ev }
            app.buttons["nextButton"].tap()
        }
        return nil
    }
}

extension XCUIElement {
    func clearAndType(_ text: String) {
        tap()
        if let v = value as? String, !v.isEmpty { typeText(String(repeating: XCUIKeyboardKey.delete.rawValue, count: v.count)) }
        typeText(text)
    }
}
