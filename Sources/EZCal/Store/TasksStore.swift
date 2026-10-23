import Foundation
import SwiftUI
import Observation

/// A reminder list (e.g. "Personal", "Work") backing calendar in Apple Reminders.
struct TaskList: Identifiable, Hashable, Sendable {
    var id: String        // "ektl|<EKCalendar identifier>", or "ektl|demo-…" in demo mode
    var listId: String    // the underlying EKCalendar identifier EventKit expects
    var name: String
    var colorHex: String
    var color: Color { Color(hex: colorHex) }
}

/// A due-dated task read from Apple Reminders (EKReminder). This is the display model used by the
/// grid, sidebar and quick-add; EventKit specifics live in `EventKitService`.
struct EZTask: Identifiable, Hashable, Sendable {
    var id: String          // "<listId>|<taskId>"
    var taskId: String      // EKReminder.calendarItemIdentifier ("<listId>|<uuid>" in demo mode)
    var listId: String
    var title: String
    var notes: String = ""
    var dueDate: Date?
    /// Whether `dueDate` carries a specific time of day (EventKit reminders can be due on a day with no time).
    var hasDueTime: Bool = false
    var isCompleted: Bool = false
    var colorHex: String
    /// EventKit priority: 0 none, 1-4 high, 5 medium, 6-9 low.
    var priority: Int = 0
    /// "daily" / "weekly" / "monthly" / "weekdays" / "custom" when the reminder repeats.
    var repeats: String?

    var color: Color { Color(hex: colorHex) }
}

/// Reminders/tasks state, kept in its own `@Observable` object so `CalendarStore` doesn't have to grow
/// another dozen stored properties for a feature that's independent of the event grid's data. Reached
/// as `store.tasks.*`; behavior lives in the `CalendarStore` extension below.
@MainActor @Observable
final class TasksState {
    var enabled: Bool
    var lists: [TaskList] = []
    var byList: [String: [EZTask]] = [:]
    private(set) var hidden: Set<String>

    init() {
        enabled = UserDefaults.standard.bool(forKey: "remindersEnabled") && EventKitService.shared.isRemindersAuthorized
        let raw = UserDefaults.standard.data(forKey: "hiddenTaskLists")
        hidden = Set(raw.flatMap { try? JSONDecoder().decode([String].self, from: $0) } ?? [])
    }

    func isVisible(_ list: TaskList) -> Bool { !hidden.contains(list.id) }

    func toggle(_ list: TaskList) {
        if hidden.contains(list.id) { hidden.remove(list.id) } else { hidden.insert(list.id) }
        UserDefaults.standard.set(try? JSONEncoder().encode(Array(hidden)), forKey: "hiddenTaskLists")
    }

    /// All tasks in visible lists, regardless of due date.
    var visible: [EZTask] {
        lists.filter(isVisible).flatMap { byList[$0.id] ?? [] }
    }

    /// Tasks with a due date, soonest first — what the grid and quick-add care about.
    var due: [EZTask] { visible.filter { $0.dueDate != nil }.sorted { $0.dueDate! < $1.dueDate! } }

    /// Tasks due on `day`, split the same way `CalendarStore.events(on:)` splits events: those with no
    /// specific time go in the all-day row, the rest get a timed marker.
    func tasks(on day: Date, cal: Calendar) -> (allDay: [EZTask], timed: [EZTask]) {
        let start = cal.startOfDay(for: day), end = cal.endOfDay(day)
        let hit = due.filter { $0.dueDate! >= start && $0.dueDate! < end }
        return (hit.filter { !$0.hasDueTime }, hit.filter(\.hasDueTime))
    }
}

/// Reminders/tasks behavior (permission, fetch, quick-add, completion). Data lives in `store.tasks`
/// (see `TasksState` above); this mirrors the shape of the Apple-Calendar-via-EventKit flow elsewhere
/// in `CalendarStore`.
extension CalendarStore {
    var defaultTaskList: TaskList? { tasks.lists.first { tasks.isVisible($0) } ?? tasks.lists.first }

    func enableReminders() async {
        do {
            guard try await EventKitService.shared.requestRemindersAccess() else {
                errorMessage = "Reminders access was denied. Enable EZCal in System Settings → Privacy & Security → Reminders."
                return
            }
            tasks.enabled = true
            UserDefaults.standard.set(true, forKey: "remindersEnabled")
            errorMessage = nil
            await loadTaskLists()
            await reloadTasks()
        } catch { errorMessage = error.localizedDescription }
    }

    func disableReminders() {
        tasks.enabled = false
        UserDefaults.standard.set(false, forKey: "remindersEnabled")
        tasks.lists = []
        tasks.byList = [:]
    }

    func loadTaskLists() async {
        guard tasks.enabled, !isDemo else { return }
        tasks.lists = EventKitService.shared.taskLists()
    }

    func reloadTasks() async {
        guard tasks.enabled, !isDemo else { return }
        var out: [String: [EZTask]] = [:]
        for list in tasks.lists where tasks.isVisible(list) {
            out[list.id] = await EventKitService.shared.tasks(for: list)
        }
        tasks.byList = out
    }

    /// Quick-add from the command palette: "task: call dentist tomorrow 3pm".
    func quickAddTask(title: String, due: Date?, hasDueTime: Bool) {
        guard tasks.enabled, let list = defaultTaskList else {
            errorMessage = "No reminder list available. Enable Reminders in Settings → Accounts."
            return
        }
        let display = title.trimmingCharacters(in: .whitespaces)
        let finalTitle = display.isEmpty ? "New task" : display

        if isDemo {
            let id = "\(list.id)|\(UUID().uuidString)"
            let t = EZTask(id: id, taskId: id, listId: list.id, title: finalTitle, dueDate: due, hasDueTime: hasDueTime, colorHex: list.colorHex)
            tasks.byList[list.id, default: []].append(t)
            return
        }
        do {
            try EventKitService.shared.saveTask(existing: nil, listId: list.listId, title: finalTitle, due: due, hasDueTime: hasDueTime, notes: "")
            Task { await self.reloadTasks() }
        } catch { errorMessage = error.localizedDescription }
    }

    /// Optimistic checkbox toggle; reverts and surfaces an error if the EventKit write fails.
    func toggleTaskCompletion(_ task: EZTask) {
        let newValue = !task.isCompleted
        setCompleted(newValue, on: task)
        guard !isDemo else { return }
        do { try EventKitService.shared.setTaskCompleted(task, completed: newValue) }
        catch {
            setCompleted(!newValue, on: task)
            errorMessage = error.localizedDescription
        }
    }

    private func setCompleted(_ value: Bool, on task: EZTask) {
        guard var arr = tasks.byList[task.listId], let i = arr.firstIndex(where: { $0.id == task.id }) else { return }
        arr[i].isCompleted = value
        tasks.byList[task.listId] = arr
    }
}
