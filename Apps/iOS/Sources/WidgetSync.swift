import SwiftUI
import WidgetKit

/// Keeps the widget in step with the app: writes the app-group cache and reloads timelines whenever the
/// loaded events change, and handles `ezcal://event/<id>` and `ezcal://day/<yyyy-MM-dd|today>` links.
struct WidgetSync: ViewModifier {
    let store: CalendarStore
    private var router: OpenEventRouter { .shared }

    /// A notification tap (or the pending one from a cold launch): open that event.
    private func consumePending() {
        guard let id = router.pendingID else { return }
        router.pendingID = nil
        Task { await store.openEvent(id) }
    }

    /// UI-test hook (demo data only): EZCAL_TEST_OPEN_EVENT=<title> posts the same `.ezcalOpenEvent`
    /// notification a notification tap would, for the first event with that title.
    private func consumeDemoOpen() async {
        guard store.isDemo, let title = ProcessInfo.processInfo.environment["EZCAL_TEST_OPEN_EVENT"] else { return }
        store.loadDemo()
        guard let ev = (store.upcoming + store.displayEvents).first(where: { $0.title == title }) else { return }
        NotificationCenter.default.post(name: .ezcalOpenEvent, object: nil, userInfo: ["eventID": ev.id])
    }

    private var known: [CalEvent] { store.displayEvents + store.upcoming }

    private func sync() {
        let cutoff = Date().addingTimeInterval(-86400)
        var seen = Set<String>()
        let mapped = known.filter { !$0.isOverlay && !$0.isDeclined && $0.end > cutoff && seen.insert($0.id).inserted }.map {
            WidgetEvent(id: $0.eventId, title: $0.title, start: $0.start, end: $0.end,
                        isAllDay: $0.isAllDay, location: $0.location, colorHex: $0.colorHex)
        }
        WidgetShared.write(WidgetCache(updated: Date(), isDemo: store.isDemo, events: mapped))
        WidgetCenter.shared.reloadAllTimelines()
    }

    func body(content: Content) -> some View {
        content
            .onChange(of: store.displayEvents) { _, _ in sync() }
            .onChange(of: store.upcoming) { _, _ in sync() }
            .onChange(of: router.pendingID) { _, _ in consumePending() }
            .task { await consumeDemoOpen(); consumePending() }
            .onOpenURL { url in
                guard url.scheme == WidgetShared.scheme else { return }
                let arg = url.path.trimmingCharacters(in: CharacterSet(charactersIn: "/"))
                switch url.host {
                case "event":
                    Task { await store.openEvent(arg) }
                case "day":
                    let f = DateFormatter(); f.dateFormat = "yyyy-MM-dd"
                    store.goTo(f.date(from: arg) ?? Date())
                default: break
                }
            }
    }
}

extension View {
    func widgetSync(_ store: CalendarStore) -> some View { modifier(WidgetSync(store: store)) }
}
