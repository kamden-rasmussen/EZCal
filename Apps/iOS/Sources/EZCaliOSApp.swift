import SwiftUI

@main
struct EZCaliOSApp: App {
    @State private var store = CalendarStore()
    @Environment(\.scenePhase) private var phase
    @AppStorage(CalendarStore.refreshIntervalKey) private var refreshInterval = CalendarStore.defaultRefreshInterval
    @AppStorage(AppearanceSetting.key) private var appearance = AppearanceSetting.system.rawValue

    init() {
        _ = OpenEventRouter.shared   // start observing notification taps before any view exists
        NotificationService.shared.start()   // delegate must exist at launch so notification taps aren't lost
    }

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .handlesWebcalLinks()
                .preferredColorScheme(AppearanceSetting(rawValue: appearance)?.scheme)
                .task {
                    if !store.eventKitEnabled && EventKitService.shared.isAuthorized { await store.enableEventKit() }
                    await store.bootstrap()
                }
                .widgetSync(store)
                .task(id: "\(refreshInterval)-\(phase == .active)") {
                    // Poll while the app is in the foreground; restarts when the setting or scene phase changes.
                    guard refreshInterval > 0, phase == .active else { return }
                    while !Task.isCancelled {
                        try? await Task.sleep(nanoseconds: UInt64(refreshInterval) * 1_000_000_000)
                        if Task.isCancelled { break }
                        await store.refreshAll()
                    }
                }
                .onChange(of: phase) { _, p in
                    if p == .active { Task { await store.refreshAll() } }
                }
        }
    }
}
