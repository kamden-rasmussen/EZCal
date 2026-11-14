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
    /// Polls until `cond` holds (for UI that settles a moment after a gesture, like the day-strip slide).
    func waitFor(_ timeout: TimeInterval = 5, _ cond: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end { if cond() { return true }; RunLoop.current.run(until: Date().addingTimeInterval(0.1)) }
        return cond()
    }
    func anyEl(_ id: String) -> XCUIElement { app.descendants(matching: .any).matching(identifier: id).firstMatch }
    var dayTitle: XCUIElement { app.buttons["dayTitle"] }

    /// Opens the toolbar menu, taps `item` and waits for `expecting` (an element the destination shows).
    /// Under load the tap on the menu button or the item can be swallowed while the menu is still animating
    /// (the item exists but the sheet never opens: #152), so wait for the item to be hittable and, if the
    /// destination does not show up, close whatever is open and go again.
    func openMenuItem(_ item: String, expecting id: String) {
        for attempt in 0..<3 {
            let button = app.buttons[item]
            if !button.exists {
                let menu = app.buttons["menuButton"]
                XCTAssertTrue(menu.waitForExistence(timeout: 10), "menu button")
                menu.tap()
            }
            guard button.waitForExistence(timeout: 5), waitUntil(timeout: 5, { button.isHittable }) else { continue }
            button.tap()
            if anyEl(id).waitForExistence(timeout: attempt == 2 ? 10 : 4) { return }
            if app.buttons[item].exists { app.coordinate(withNormalizedOffset: CGVector(dx: 0.9, dy: 0.6)).tap() }   // dismiss a menu left open
        }
        XCTFail("\(item) did not open \(id)")
    }

    /// Polls `condition` every 0.1 s until it holds or the timeout passes (a deterministic wait that is not a sleep).
    @discardableResult
    func waitUntil(timeout: TimeInterval, _ condition: () -> Bool) -> Bool {
        let end = Date().addingTimeInterval(timeout)
        while Date() < end {
            if condition() { return true }
            RunLoop.current.run(until: Date().addingTimeInterval(0.1))
        }
        return condition()
    }

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

    /// Demo events that belong to another person's calendar (overlay): shown in the grid but read-only, so a
    /// long-press does not lift them and they get no resize handles. Monday's first event ("Investor prep") is one,
    /// which made the drag/resize tests fail every Monday (#171).
    static let readOnlyDemoEvents = ["Investor prep", "1:1 with Dana", "Demo prep"]

    /// Goes to Day view and returns a timed event block that can be dragged and resized, from the first day in the
    /// coming week that has one: not an overlay event, and tall enough to carry resize handles when there is a
    /// choice. The element is found by its title, so it keeps resolving to the same event after it is edited.
    func firstDayEvent() -> XCUIElement {
        selectTab("Day")
        let blocks = app.descendants(matching: .any).matching(identifier: "dayEvent")
        for _ in 0..<7 {
            if blocks.firstMatch.waitForExistence(timeout: 1) {
                let editable = blocks.allElementsBoundByIndex.filter { !Self.readOnlyDemoEvents.contains($0.label) }
                if let pick = editable.first(where: { $0.frame.height > 40 }) ?? editable.first {
                    let title = pick.label
                    return scrolledIntoView(blocks.matching(NSPredicate(format: "label == %@", title)).firstMatch)
                }
            }
            app.buttons["nextButton"].tap()
        }
        XCTFail("no editable timed events in the next week")
        return blocks.firstMatch
    }

    /// The time grid opens scrolled to the first event, so the now line (an accessibility element inside the
    /// scroll view) is only exposed while its hour is on screen; which hour that is depends on the time of day
    /// the test runs (#141). Scroll the grid in both directions until it shows up.
    func revealNowLine(timeout: TimeInterval = 3) -> Bool {
        let line = anyEl("nowLine")
        if line.waitForExistence(timeout: timeout) { return true }
        let grid = app.scrollViews.firstMatch
        for _ in 0..<5 {   // down the day first (evening is the common case), then back past the start
            grid.swipeUp(velocity: .fast)
            if line.waitForExistence(timeout: 1) { return true }
        }
        for _ in 0..<10 {
            grid.swipeDown(velocity: .fast)
            if line.waitForExistence(timeout: 1) { return true }
        }
        return false
    }

    /// The day grid opens scrolled to "now" when today is showing (18:00 at 8 pm), so an event from earlier in the
    /// day exists in the accessibility tree but sits off screen, and raw coordinates relative to it land on the
    /// nav bar (#68). Scroll the grid until the element is comfortably inside the visible grid area.
    func scrolledIntoView(_ el: XCUIElement) -> XCUIElement {
        let grid = app.scrollViews.firstMatch
        let screen = app.frame
        func inView() -> Bool { el.isHittable && el.frame.minY > screen.height * 0.3 && el.frame.maxY < screen.height * 0.75 }
        for _ in 0..<10 where !inView() {
            // Content above the visible area: drag down to reveal it; below: drag up.
            let up = el.frame.midY > screen.midY
            let a = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: up ? 0.7 : 0.3))
            let b = grid.coordinate(withNormalizedOffset: CGVector(dx: 0.1, dy: up ? 0.4 : 0.6))
            a.press(forDuration: 0.05, thenDragTo: b)
        }
        return el
    }

    /// After a drag/resize: wait until either the edit took effect or the "This event / All events" scope prompt is
    /// up, picking "This event" if so. Recurring events ask, and under load the prompt can arrive well after the
    /// fixed 1.5 s `chooseScopeIfAsked` waits, which made the test read the old value (#152).
    @discardableResult
    func finishEdit(timeout: TimeInterval = 10, until changed: () -> Bool) -> Bool {
        let b = app.buttons["This event"]
        waitUntil(timeout: timeout) { changed() || b.exists }
        if b.exists && b.isHittable { b.tap() }
        return waitUntil(timeout: timeout, changed)
    }

    /// Taps an agenda row and opens the detail sheet. A meeting stacked across calendars (the demo's Sunday "Team
    /// planning", which is the first row on Sundays) opens a calendar list first; pick its first copy.
    func openAgendaRow(_ row: XCUIElement) {
        row.tap()
        if anyEl("stackCalendarsHeader").waitForExistence(timeout: 1.5) {
            app.buttons.matching(NSPredicate(format: "label CONTAINS 'open event'")).firstMatch.tap()
        }
        XCTAssertTrue(app.staticTexts["detailTitle"].waitForExistence(timeout: 5), "detail sheet should open")
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

    /// A week-grid event block that is on screen. Which events a week shows and where the grid is scrolled depend on
    /// the weekday and the time of day (the demo week is Monday-based but the grid week starts on Sunday, and the
    /// grid opens at "now" minus two hours), so pick a roomy block from whichever week has one and scroll it into
    /// view instead of assuming a fixed position.
    func visibleWeekEvent() -> XCUIElement? {
        selectTab("Day")
        pickGrid("Week")
        XCTAssertTrue(app.scrollViews.firstMatch.waitForExistence(timeout: 5))
        for _ in 0..<3 {
            let blocks = app.descendants(matching: .any).matching(identifier: "weekDayEvent")
            _ = blocks.firstMatch.waitForExistence(timeout: 3)
            // Wide enough for the drag to land in a neighbouring column, tall enough to carry resize handles.
            if let ev = blocks.allElementsBoundByIndex.first(where: { $0.frame.height > 40 && $0.frame.width > 40 }) {
                let shown = scrolledIntoView(ev)
                if shown.isHittable { return shown }
            }
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
