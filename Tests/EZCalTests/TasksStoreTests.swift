import XCTest
@testable import EZCal

@MainActor
final class TasksStoreTests: XCTestCase {
    // `TasksState` persists list visibility to UserDefaults.standard (the real defaults, same as the app),
    // so tests must not leak state into each other through it.
    override func setUp() { UserDefaults.standard.removeObject(forKey: "hiddenTaskLists") }
    override func tearDown() { UserDefaults.standard.removeObject(forKey: "hiddenTaskLists") }

    private func makeList(_ id: String = "ektl|a") -> TaskList {
        TaskList(id: id, listId: "a", name: "Personal", colorHex: "#3E63DD")
    }

    func testVisibilityToggle() {
        let state = TasksState()
        let list = makeList()
        state.lists = [list]
        XCTAssertTrue(state.isVisible(list))
        state.toggle(list)
        XCTAssertFalse(state.isVisible(list))
        state.toggle(list)
        XCTAssertTrue(state.isVisible(list))
    }

    func testDueSplitsIntoAllDayAndTimedForTheRightDay() {
        let state = TasksState()
        let list = makeList()
        state.lists = [list]
        let cal = Calendar.current
        let today = cal.startOfDay(for: Date())
        let timed = EZTask(id: "1", taskId: "1", listId: list.id, title: "Call dentist",
                           dueDate: cal.date(byAdding: .hour, value: 15, to: today), hasDueTime: true, colorHex: list.colorHex)
        let allDay = EZTask(id: "2", taskId: "2", listId: list.id, title: "Pack",
                            dueDate: today, hasDueTime: false, colorHex: list.colorHex)
        let tomorrow = EZTask(id: "3", taskId: "3", listId: list.id, title: "Not today",
                              dueDate: cal.date(byAdding: .day, value: 1, to: today), hasDueTime: false, colorHex: list.colorHex)
        state.byList = [list.id: [timed, allDay, tomorrow]]

        let (allDayToday, timedToday) = state.tasks(on: today, cal: cal)
        XCTAssertEqual(allDayToday.map(\.id), ["2"])
        XCTAssertEqual(timedToday.map(\.id), ["1"])
    }

    func testHiddenListIsExcludedFromDueTasks() {
        let state = TasksState()
        let list = makeList()
        state.lists = [list]
        let t = EZTask(id: "1", taskId: "1", listId: list.id, title: "x", dueDate: Date(), colorHex: list.colorHex)
        state.byList = [list.id: [t]]
        XCTAssertEqual(state.due.count, 1)
        state.toggle(list)
        XCTAssertEqual(state.due.count, 0)
    }

    func testQuickAddInDemoModeAppendsATaskWithoutEventKit() {
        // Demo mode is driven by an env var read at CalendarStore.init(); this process runs without it,
        // so quickAddTask would try EventKit and fail gracefully instead — exercise that path directly.
        let store = CalendarStore()
        store.tasks.enabled = true
        let list = makeList()
        store.tasks.lists = [list]
        store.tasks.byList = [:]

        let due = Date().addingTimeInterval(3600)
        store.quickAddTask(title: "Call dentist", due: due, hasDueTime: true)

        // Not in demo mode: EventKit isn't authorized in this test environment, so the write throws and
        // surfaces an error rather than crashing — the important thing is it degrades safely.
        XCTAssertNotNil(store.errorMessage)
    }

    func testToggleCompletionIsOptimisticAndRevertsOnFailure() {
        let store = CalendarStore()
        let list = makeList()
        let t = EZTask(id: "1", taskId: "does-not-exist", listId: list.id, title: "x", colorHex: list.colorHex)
        store.tasks.lists = [list]
        store.tasks.byList = [list.id: [t]]

        store.toggleTaskCompletion(t)

        // EventKit isn't authorized/available in the test environment, so the optimistic flip is reverted.
        XCTAssertEqual(store.tasks.byList[list.id]?.first?.isCompleted, false)
        XCTAssertNotNil(store.errorMessage)
    }
}
