import SwiftUI

@main
struct EZCaliOSApp: App {
    @State private var store = CalendarStore()
    @Environment(\.scenePhase) private var phase
    @AppStorage(AppearanceSetting.key) private var appearance = AppearanceSetting.system.rawValue

    var body: some Scene {
        WindowGroup {
            RootView()
                .environment(store)
                .preferredColorScheme(AppearanceSetting(rawValue: appearance)?.scheme)
                .task {
                    if !store.eventKitEnabled && EventKitService.shared.isAuthorized { await store.enableEventKit() }
                    await store.bootstrap()
                }
                .widgetSync(store)
                .onChange(of: phase) { _, p in
                    if p == .active { Task { await store.refreshAll() } }
                }
        }
    }
}
