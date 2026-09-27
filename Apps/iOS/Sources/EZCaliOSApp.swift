import SwiftUI

@main
struct EZCaliOSApp: App {
    @State private var store = CalendarStore()

    var body: some Scene {
        WindowGroup {
            Text("EZCal")
                .environment(store)
        }
    }
}
