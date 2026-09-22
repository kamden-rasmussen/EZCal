import Foundation

/// Issue #3: edit/delete scope for recurring events. Kept in its own file so the core save/delete
/// flows in CalendarStore.swift only need small, additive hooks into this logic.
extension CalendarStore {
    /// Edit entry point used by the grid, detail card and keyboard shortcuts: recurring events ask
    /// which occurrences first, everything else opens the editor directly.
    func requestEdit(_ e: CalEvent) {
        if e.isRecurring { sheet = .recurrenceScope(e, .edit) } else { editDraft(e) }
    }

    /// Delete entry point, mirroring `requestEdit`: recurring events ask first, everything else uses
    /// the existing plain confirmation.
    func requestDelete(_ e: CalEvent) {
        if e.isRecurring { sheet = .recurrenceScope(e, .delete) } else { deleteRequest = e }
    }

    /// Called by RecurrenceScopeView once the person picks a scope.
    func chooseRecurrenceScope(_ scope: RecurrenceScope, for e: CalEvent, action: RecurrenceAction) {
        switch action {
        case .edit: editDraft(e, scope: scope)
        case .delete: Task { await delete(e, scope: scope) }
        }
    }

    // MARK: - Google: instance vs. series vs. split

    /// Deletes `e` on Google Calendar according to `scope` (see `RecurrenceScope.googleDeleteTarget`).
    func deleteGoogleRecurring(_ e: CalEvent, scope: RecurrenceScope) async throws {
        let api = GoogleAPI(accountId: e.accountId)
        switch RecurrenceScope.googleDeleteTarget(scope: scope, eventId: e.eventId, recurringEventId: e.recurringEventId) {
        case .instance(let id), .series(let id):
            try await api.deleteEvent(calendarId: e.calendarId, eventId: id)
        case .truncateSeries(let masterId):
            let master = try await api.getEvent(calendarId: e.calendarId, eventId: masterId)
            let rules = RecurrenceRule.truncated(master.recurrence ?? [], before: e.start)
            try await api.patchEvent(calendarId: e.calendarId, eventId: masterId, body: ["recurrence": rules])
        }
    }

    /// Applies an edit (`body`, already built by `save(_:)`) to `existing` on Google Calendar per `scope`.
    func patchGoogleRecurring(existing: CalEvent, body: [String: Any], calendarId: String,
                              withMeet: Bool, scope: RecurrenceScope) async throws {
        let api = GoogleAPI(accountId: existing.accountId)
        switch RecurrenceScope.googlePatchTarget(scope: scope, eventId: existing.eventId, recurringEventId: existing.recurringEventId) {
        case .instance(let id), .series(let id):
            try await api.patchEvent(calendarId: calendarId, eventId: id, body: body, withMeet: withMeet)
        case .splitSeries(let masterId):
            // Truncate the old series to end right before this occurrence, then start a fresh one
            // here carrying the edited fields and the original recurrence pattern.
            let master = try await api.getEvent(calendarId: calendarId, eventId: masterId)
            let rules = RecurrenceRule.truncated(master.recurrence ?? [], before: existing.start)
            try await api.patchEvent(calendarId: calendarId, eventId: masterId, body: ["recurrence": rules])
            var newSeries = body
            newSeries["recurrence"] = master.recurrence ?? []
            try await api.insertEvent(calendarId: calendarId, body: newSeries, withMeet: withMeet)
        }
    }
}
