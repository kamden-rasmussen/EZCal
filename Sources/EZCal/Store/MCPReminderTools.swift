#if os(macOS)
import Foundation

/// The Apple Reminders tools exposed over MCP (issue #88). They go through `EventKitService`, the same path the app's
/// quick-add and checkboxes use, and need Reminders to be switched on in EZCal (Settings → Accounts).
@MainActor
enum MCPReminderTools {
    static func all(store: CalendarStore) -> [MCPTool] {
        let h = MCPReminderHelper(store: store)
        func obj(_ props: [String: Any], required: [String] = []) -> [String: Any] { MCPTools.obj(props, required: required) }
        func str(_ d: String) -> [String: Any] { MCPTools.str(d) }
        let priorities: [String: Any] = ["type": "string", "enum": ["none", "low", "medium", "high"], "description": "Priority."]
        let repeats: [String: Any] = ["type": "string", "enum": ["none", "daily", "weekly", "monthly", "weekdays"], "description": "Repeat rule (needs a due date)."]
        return [
            MCPTool(name: "list_reminder_lists", description: "List the user's Apple Reminders lists with ids and whether each is shown in EZCal.",
                    schema: obj([:]), writes: false, title: "List reminder lists") { _ in try h.listLists() },

            MCPTool(name: "list_reminders",
                    description: "List reminders, soonest due first (undated last). By default only incomplete reminders in lists shown in EZCal.",
                    schema: obj([
                        "list_ids": ["type": "array", "items": ["type": "string"], "description": "Only these lists (ids from list_reminder_lists). Default: visible lists."],
                        "due_before": str("Only reminders due before this ISO 8601 date or date-time (undated ones are left out)."),
                        "query": str("Case-insensitive text match on title and notes."),
                        "include_completed": ["type": "boolean", "description": "Also return completed reminders (default false)."],
                        "limit": ["type": "integer", "description": "Max reminders to return (default 50, max 200)."],
                    ]), writes: false, title: "List reminders") { try await h.list($0) },

            MCPTool(name: "create_reminder", description: "Create a reminder in the given list (default: the first list shown in EZCal).",
                    schema: obj([
                        "title": str("Reminder title."),
                        "due": str("Due: ISO 8601 date-time, or a date (YYYY-MM-DD) for a reminder due that day with no time."),
                        "list_id": str("Target list id from list_reminder_lists."),
                        "notes": str("Notes."),
                        "priority": priorities,
                        "repeat": repeats,
                    ], required: ["title"]), writes: true, title: "Create reminder") { try await h.create($0) },

            MCPTool(name: "update_reminder",
                    description: "Change a reminder or mark it done/not done. Only the fields you pass are changed. current_title must match the reminder as it is now (copy it from list_reminders); a mismatch is refused.",
                    schema: obj([
                        "reminder_id": str("Reminder id."),
                        "current_title": str("The reminder's current title, as returned by list_reminders."),
                        "title": str("New title."),
                        "due": str("New due date or date-time (empty string clears it)."),
                        "notes": str("New notes (empty string clears them)."),
                        "priority": priorities,
                        "repeat": repeats,
                        "completed": ["type": "boolean", "description": "true marks it done, false reopens it."],
                    ], required: ["reminder_id", "current_title"]), writes: true, title: "Update reminder", destructive: true) { try await h.update($0) },

            MCPTool(name: "delete_reminder",
                    description: "Delete a reminder and report what was deleted. current_title must match the reminder as it is now; a mismatch is refused.",
                    schema: obj([
                        "reminder_id": str("Reminder id."),
                        "current_title": str("The reminder's current title, as returned by list_reminders."),
                    ], required: ["reminder_id", "current_title"]), writes: true, title: "Delete reminder", destructive: true) { try await h.delete($0) },
        ]
    }
}

@MainActor
struct MCPReminderHelper {
    let store: CalendarStore
    private var cal: Calendar { store.cal }

    // MARK: Arguments

    private func string(_ a: [String: Any], _ k: String) -> String? { a[k] as? String }
    private func required(_ a: [String: Any], _ k: String) throws -> String {
        guard let s = string(a, k)?.trimmingCharacters(in: .whitespacesAndNewlines), !s.isEmpty else {
            throw MCPToolError("Missing required argument `\(k)`.")
        }
        return s
    }
    private func due(_ s: String, _ k: String) throws -> MCPDate.Parsed {
        guard let p = MCPDate.parse(s, calendar: cal) else {
            throw MCPToolError("`\(k)` must be ISO 8601 (e.g. 2026-10-12T14:30:00-06:00 or 2026-10-12), got \"\(s)\".")
        }
        return p
    }
    private func priority(_ a: [String: Any]) throws -> Int? {
        switch string(a, "priority") {
        case nil: return nil
        case "none": return 0
        case "high": return 1
        case "medium": return 5
        case "low": return 9
        case let s?: throw MCPToolError("`priority` must be none, low, medium or high, got \"\(s)\".")
        }
    }
    private func recurrence(_ a: [String: Any]) throws -> RecurrenceOption? {
        guard let r = string(a, "repeat") else { return nil }
        guard let opt = RecurrenceOption(rawValue: r) else { throw MCPToolError("`repeat` must be none, daily, weekly, monthly or weekdays.") }
        return opt
    }

    // MARK: Output

    private func priorityName(_ p: Int) -> String { p == 0 ? "none" : p <= 4 ? "high" : p == 5 ? "medium" : "low" }

    private func summary(_ t: EZTask) -> [String: Any] {
        var d: [String: Any] = ["id": t.id, "list_id": t.listId, "list": store.tasks.lists.first { $0.id == t.listId }?.name ?? "",
                                "title": t.title, "completed": t.isCompleted]
        if let due = t.dueDate { d["due"] = t.hasDueTime ? MCPDate.string(due, timeZone: cal.timeZone) : MCPDate.day(due, calendar: cal) }
        if !t.notes.isEmpty { d["notes"] = t.notes }
        if t.priority != 0 { d["priority"] = priorityName(t.priority) }
        if let r = t.repeats { d["repeat"] = r }
        return d
    }

    // MARK: Access

    private func requireAccess() throws {
        guard store.tasks.enabled else {
            throw MCPToolError("Reminders isn't switched on in EZCal. Ask the user to enable it in EZCal → Settings → Accounts.")
        }
    }
    private func requireWritable() throws {
        try requireAccess()
        if store.isDemo { throw MCPToolError("Reminders can't be changed in demo mode.") }
    }

    private func fetch(_ lists: [TaskList]) async -> [EZTask] {
        if store.isDemo { let ids = Set(lists.map(\.id)); return store.tasks.byList.filter { ids.contains($0.key) }.values.flatMap { $0 } }
        var out: [EZTask] = []
        for l in lists { out += await EventKitService.shared.tasks(for: l) }
        return out
    }

    private func locate(_ id: String) throws -> EZTask {
        if store.isDemo, let t = store.tasks.byList.values.joined().first(where: { $0.id == id }) { return t }
        if let t = EventKitService.shared.task(withId: id) { return t }
        throw MCPToolError("No reminder with id \"\(id)\" (it may have been deleted).")
    }

    private func confirmCurrent(_ a: [String: Any], _ t: EZTask) throws {
        let title = try required(a, "current_title")
        guard title == t.title.trimmingCharacters(in: .whitespacesAndNewlines) else {
            throw MCPToolError("`reminder_id` points at a different reminder than current_title describes, so nothing was changed. "
                               + "The reminder with that id is \"\(t.title)\" on \(summary(t)["list"] ?? ""). Re-check with list_reminders.")
        }
    }

    // MARK: Tools

    func listLists() throws -> Any {
        try requireAccess()
        return ["lists": store.tasks.lists.map { ["id": $0.id, "name": $0.name, "visible": store.tasks.isVisible($0)] as [String: Any] }]
    }

    func list(_ a: [String: Any]) async throws -> Any {
        try requireAccess()
        var lists = store.tasks.lists.filter(store.tasks.isVisible)
        if let ids = a["list_ids"] as? [String] {
            if let bad = ids.first(where: { id in !store.tasks.lists.contains { $0.id == id } }) { throw MCPToolError("Unknown list id \"\(bad)\". Call list_reminder_lists.") }
            lists = store.tasks.lists.filter { ids.contains($0.id) }
        }
        var tasks = await fetch(lists)
        if (a["include_completed"] as? Bool) != true { tasks = tasks.filter { !$0.isCompleted } }
        if let s = string(a, "due_before") { let limit = try due(s, "due_before").date; tasks = tasks.filter { $0.dueDate.map { $0 < limit } ?? false } }
        if let q = string(a, "query")?.trimmingCharacters(in: .whitespaces), !q.isEmpty {
            tasks = tasks.filter { $0.title.localizedCaseInsensitiveContains(q) || $0.notes.localizedCaseInsensitiveContains(q) }
        }
        tasks.sort { ($0.dueDate ?? .distantFuture, $0.title) < ($1.dueDate ?? .distantFuture, $1.title) }
        let limit = min(max((a["limit"] as? Int) ?? 50, 1), 200)
        var out: [String: Any] = ["reminders": tasks.prefix(limit).map(summary), "total": tasks.count]
        if tasks.count > limit { out["note"] = "Showing the first \(limit); narrow with due_before, list_ids or query." }
        return out
    }

    func create(_ a: [String: Any]) async throws -> Any {
        try requireWritable()
        let title = try required(a, "title")
        let list: TaskList
        if let id = string(a, "list_id") {
            guard let l = store.tasks.lists.first(where: { $0.id == id }) else { throw MCPToolError("Unknown list id \"\(id)\". Call list_reminder_lists.") }
            list = l
        } else if let l = store.defaultTaskList { list = l }
        else { throw MCPToolError("No reminder list is available.") }
        let parsed = try string(a, "due").flatMap { $0.isEmpty ? nil : try due($0, "due") }
        let repeatRule = try recurrence(a)
        if let r = repeatRule, r != .none, parsed == nil { throw MCPToolError("A repeating reminder needs a `due` date.") }
        let id: String
        do {
            id = try EventKitService.shared.saveTask(existing: nil, listId: list.listId, title: title, due: parsed?.date,
                                                     hasDueTime: parsed.map { !$0.dateOnly } ?? false, notes: string(a, "notes") ?? "",
                                                     priority: try priority(a), recurrence: repeatRule)
        } catch { throw MCPToolError((error as? APIError).map { "\($0)" } ?? error.localizedDescription) }
        await store.reloadTasks()
        var out: [String: Any] = ["created": true]
        if let t = EventKitService.shared.task(withId: id) { out["reminder"] = summary(t) }
        return out
    }

    func update(_ a: [String: Any]) async throws -> Any {
        try requireWritable()
        let t = try locate(try required(a, "reminder_id"))
        try confirmCurrent(a, t)
        var title = t.title, notes = t.notes, dueDate = t.dueDate, hasTime = t.hasDueTime
        if let n = string(a, "title") {
            let n = n.trimmingCharacters(in: .whitespaces)
            if n.isEmpty { throw MCPToolError("`title` can't be empty.") }
            title = n
        }
        if let n = string(a, "notes") { notes = n }
        if let s = string(a, "due") {
            if s.isEmpty { dueDate = nil; hasTime = false } else { let p = try due(s, "due"); dueDate = p.date; hasTime = !p.dateOnly }
        }
        let repeatRule = try recurrence(a)
        if let r = repeatRule, r != .none, dueDate == nil { throw MCPToolError("A repeating reminder needs a due date.") }
        if dueDate == nil, repeatRule == nil, t.repeats != nil { throw MCPToolError("This reminder repeats; clear it with `repeat: none` before removing its due date.") }
        do {
            try EventKitService.shared.saveTask(existing: t, listId: t.listId, title: title, due: dueDate, hasDueTime: hasTime, notes: notes,
                                                priority: try priority(a), recurrence: repeatRule)
            if let done = a["completed"] as? Bool, done != t.isCompleted { try EventKitService.shared.setTaskCompleted(t, completed: done) }
        } catch { throw MCPToolError((error as? APIError).map { "\($0)" } ?? error.localizedDescription) }
        await store.reloadTasks()
        var out: [String: Any] = ["updated": true]
        if let now = EventKitService.shared.task(withId: t.taskId) { out["reminder"] = summary(now) }
        return out
    }

    func delete(_ a: [String: Any]) async throws -> Any {
        try requireWritable()
        let t = try locate(try required(a, "reminder_id"))
        try confirmCurrent(a, t)
        let summarized = summary(t)
        do { try EventKitService.shared.deleteTask(t) } catch { throw MCPToolError(error.localizedDescription) }
        await store.reloadTasks()
        return ["deleted": true, "reminder": summarized]
    }
}
#endif
