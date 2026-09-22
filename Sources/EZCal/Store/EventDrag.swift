import Foundation

/// Live preview shown while an event is being dragged (move or resize) or keyboard-nudged. Transient UI
/// state only — never persisted, never part of `displayEvents`.
struct EventDragPreview: Equatable {
    enum Kind: Equatable { case move, resize }
    var kind: Kind
    var event: CalEvent   // the original event, for the ghost's title/color
    var day: Date         // which day column the ghost belongs in
    var start: Date
    var end: Date
}

/// Drag-to-move / drag-to-resize commit logic (issue #1). The gestures and ghost rendering live in
/// `EventBlock` / `DayColumn` (`Views/TimeGridView.swift`); the snap/time math lives in `EventDragMath`.
extension CalendarStore {
    /// Esc cancels an in-progress drag: the ghost disappears immediately, and the gesture's `onEnded`
    /// (which fires once the mouse is released) finds no matching preview and does nothing.
    func cancelDrag() {
        dragPreview = nil
        dragCancelled = true
    }

    /// Commits a drag or keyboard nudge: saves the new time through the right backend, updates an attached
    /// Zoom meeting if any, and rolls the block back with an error banner if the save fails. Recurring
    /// events are already resolved to a single occurrence's `eventId` upstream, so this only ever moves
    /// that one instance, matching the editor's `save(_:)`.
    func applyTimeChange(to e: CalEvent, start: Date, end: Date) async {
        guard e.canEdit, !e.isOverlay, !e.isBusyOnly, !e.isAllDay else { return }
        let original = (e.start, e.end)
        setDisplayedTime(eventID: e.id, start: start, end: end)   // optimistic; rolled back below on failure

        guard !isDemo else { return }   // nothing real to save to in demo mode; keep the optimistic move

        do {
            if e.isEventKit {
                try EventKitService.shared.save(existing: e, calendarId: e.calendarId, title: e.title,
                                                start: start, end: end, allDay: false,
                                                location: e.location, notes: nil)
            } else {
                let body: [String: Any] = [
                    "start": ["dateTime": RFC3339.string(start), "timeZone": TimeZone.current.identifier],
                    "end": ["dateTime": RFC3339.string(end), "timeZone": TimeZone.current.identifier],
                ]
                try await GoogleAPI(accountId: e.accountId).patchEvent(calendarId: e.calendarId, eventId: e.eventId, body: body)
            }
            if let zid = e.zoomMeetingID {
                await ZoomAPI.updateMeeting(id: zid, topic: e.title, start: start, end: end)
            }
            await reload()
            await refreshUpcoming()
        } catch {
            setDisplayedTime(eventID: e.id, start: original.0, end: original.1)
            errorMessage = error.localizedDescription
        }
    }

    /// Keyboard equivalent of dragging: ⌥↑/↓ moves the focused event 15 minutes, ⌥⇧↑/↓ resizes it (bottom
    /// edge, 15-minute minimum). No-op for read-only events, overlays and all-day events.
    func nudgeFocused(minutes: Int, resize: Bool) {
        guard let e = focusedEvent, e.canEdit, !e.isOverlay, !e.isBusyOnly, !e.isAllDay else { return }
        let (s, en) = resize
            ? EventDragMath.resized(start: e.start, end: e.end, minutesDelta: minutes, cal: cal)
            : EventDragMath.moved(start: e.start, end: e.end, minutesDelta: minutes, dayDelta: 0, cal: cal)
        Task { await applyTimeChange(to: e, start: s, end: en) }
    }
}
