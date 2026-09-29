import Foundation
import UserNotifications


/// Posted when the user taps a meeting notification (or its "Open" action) so the app can focus that
/// event. A plain NotificationCenter post rather than a stored CalendarStore reference keeps this file a
/// thin UNUserNotificationCenter wrapper — see NotificationPlanner.swift for the testable scheduling logic.
extension Notification.Name {
    static let ezcalOpenEvent = Notification.Name("ezcalOpenEvent")
}

/// Wraps UNUserNotificationCenter: permission, the Join/Open actions, and diffing pending requests
/// against a fresh `NotificationPlanner.plan()` so refreshes reschedule without duplicating or leaking
/// stale reminders. Deliberately dumb — all "which event gets which trigger" logic lives in
/// NotificationPlanner so it can be unit tested on its own.
@MainActor
final class NotificationService: NSObject, UNUserNotificationCenterDelegate {
    static let shared = NotificationService()

    // Plain (non-isolated) constants: the delegate callbacks below run off the main actor.
    private nonisolated static let idPrefix = "meeting|"
    private nonisolated static let categoryJoin = "EZCAL_MEETING_JOIN"     // Join + Open
    private nonisolated static let categoryOpenOnly = "EZCAL_MEETING_OPEN" // Open only (no video link)
    private nonisolated static let joinAction = "JOIN"
    private nonisolated static let openAction = "OPEN"

    private let center = UNUserNotificationCenter.current()
    private var categoriesRegistered = false

    private override init() { super.init() }

    private func registerCategoriesIfNeeded() {
        guard !categoriesRegistered else { return }
        categoriesRegistered = true
        center.delegate = self
        let join = UNNotificationAction(identifier: Self.joinAction, title: "Join", options: [.foreground])
        let open = UNNotificationAction(identifier: Self.openAction, title: "Open", options: [.foreground])
        center.setNotificationCategories([
            UNNotificationCategory(identifier: Self.categoryJoin, actions: [join, open], intentIdentifiers: [], options: []),
            UNNotificationCategory(identifier: Self.categoryOpenOnly, actions: [open], intentIdentifiers: [], options: []),
        ])
    }

    /// Only ever called right before the first real schedule — never at launch — so permission is
    /// requested lazily, once the user has actually turned reminders on.
    private func ensureAuthorized() async -> Bool {
        registerCategoriesIfNeeded()
        let settings = await center.notificationSettings()
        switch settings.authorizationStatus {
        case .authorized, .provisional: return true
        case .notDetermined: return (try? await center.requestAuthorization(options: [.alert, .sound])) ?? false
        default: return false // denied / restricted — degrade silently; Settings surfaces this to the user
        }
    }

    /// Replaces our pending reminders with exactly `planned`: drops ones no longer wanted (event deleted,
    /// declined, moved, or reminders turned off) and adds new ones, leaving already-pending requests alone
    /// so a routine refresh never duplicates or resets a countdown the user is already looking at.
    func reschedule(_ planned: [PlannedNotification]) async {
        guard !planned.isEmpty else {
            let pending = await center.pendingNotificationRequests()
            let ours = pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) }
            if !ours.isEmpty { center.removePendingNotificationRequests(withIdentifiers: ours) }
            return
        }
        guard await ensureAuthorized() else { return }
        let pending = await center.pendingNotificationRequests()
        let ourPending = Set(pending.map(\.identifier).filter { $0.hasPrefix(Self.idPrefix) })
        let desired = Set(planned.map(\.id))

        let stale = ourPending.subtracting(desired)
        if !stale.isEmpty { center.removePendingNotificationRequests(withIdentifiers: Array(stale)) }

        for p in planned where !ourPending.contains(p.id) {
            try? await center.add(request(for: p))
        }
    }

    private func request(for p: PlannedNotification) -> UNNotificationRequest {
        let content = UNMutableNotificationContent()
        content.title = p.title
        content.body = p.body
        content.sound = .default
        content.categoryIdentifier = p.hasJoinLink ? Self.categoryJoin : Self.categoryOpenOnly
        content.userInfo = ["eventID": p.eventID, "joinURL": p.joinURLString ?? ""]
        let interval = max(p.fireDate.timeIntervalSinceNow, 1)
        return UNNotificationRequest(identifier: p.id, content: content,
                                      trigger: UNTimeIntervalNotificationTrigger(timeInterval: interval, repeats: false))
    }

    /// EZCAL_DEMO's "Send test notification" button (Settings → General) — a real system notification
    /// with both actions, no calendar data touched.
    @discardableResult
    func sendTest() async -> Bool {
        guard await ensureAuthorized() else { return false }
        let content = UNMutableNotificationContent()
        content.title = "Test meeting"
        content.body = "This is what a meeting reminder looks like."
        content.sound = .default
        content.categoryIdentifier = Self.categoryJoin
        content.userInfo = ["eventID": "", "joinURL": "https://zoom.us/j/000000000"]
        let request = UNNotificationRequest(identifier: "test|\(UUID().uuidString)", content: content,
                                             trigger: UNTimeIntervalNotificationTrigger(timeInterval: 2, repeats: false))
        try? await center.add(request)
        return true
    }

    // MARK: - UNUserNotificationCenterDelegate (called on an arbitrary thread, hence `nonisolated`)

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                             willPresent notification: UNNotification) async -> UNNotificationPresentationOptions {
        [.banner, .sound]   // show it even while EZCal is frontmost
    }

    nonisolated func userNotificationCenter(_ center: UNUserNotificationCenter,
                                             didReceive response: UNNotificationResponse) async {
        let info = response.notification.request.content.userInfo
        let eventID = info["eventID"] as? String ?? ""
        if response.actionIdentifier == Self.joinAction,
           let s = info["joinURL"] as? String, !s.isEmpty, let url = URL(string: s) {
            await MainActor.run { Platform.open(url) }
            return
        }
        // The "Open" action, or a plain click on the notification itself: focus the event in the app.
        guard !eventID.isEmpty else { return }
        await MainActor.run {
            NotificationCenter.default.post(name: .ezcalOpenEvent, object: nil, userInfo: ["eventID": eventID])
        }
    }
}
