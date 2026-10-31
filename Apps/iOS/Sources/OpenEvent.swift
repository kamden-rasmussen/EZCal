import SwiftUI

/// Catches `.ezcalOpenEvent` (posted by the notification tap handler) from app launch on, so a tap that
/// cold-launches the app isn't lost before any view exists to observe it.
@MainActor @Observable
final class OpenEventRouter {
    static let shared = OpenEventRouter()
    var pendingID: String?
    private var token: NSObjectProtocol?

    private init() {
        token = NotificationCenter.default.addObserver(forName: .ezcalOpenEvent, object: nil, queue: .main) { [weak self] note in
            guard let id = note.userInfo?["eventID"] as? String, !id.isEmpty else { return }
            MainActor.assumeIsolated { self?.pendingID = id }
        }
    }
}

extension CalendarStore {
    /// Goes to the event's day and presents its detail sheet. `id` is a CalEvent `id` (notifications) or
    /// `eventId` (ezcal:// links). Searches what's loaded plus the 36h `upcoming` window; if it isn't
    /// there (e.g. the app was asleep), refreshes `upcoming` once and retries. Returns false if not found.
    @discardableResult
    func openEvent(_ id: String) async -> Bool {
        func find() -> CalEvent? {
            (upcoming + displayEvents).first { $0.id == id || $0.eventId == id }
        }
        var ev = find()
        if ev == nil, !isDemo {
            await refreshUpcoming()
            ev = find()
        }
        guard let ev else { return false }
        goTo(ev.start)          // reloads the visible range around the event if it was outside it
        sheet = .detail(ev)
        return true
    }
}
