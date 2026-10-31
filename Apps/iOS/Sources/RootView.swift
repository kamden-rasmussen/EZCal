import SwiftUI
import EventKit

enum HomeTab: String, CaseIterable, Identifiable {
    case agenda = "Agenda", day = "Day"
    var id: String { rawValue }
}

struct RootView: View {
    @Environment(CalendarStore.self) private var store
    @State private var tab: HomeTab = .agenda
    @State private var gridMode: ViewMode = .day
    @State private var showCalendars = false
    @State private var showSettings = false
    @State private var authStatus = EKEventStore.authorizationStatus(for: .event)

    private var needsConnect: Bool { !store.isDemo && !store.eventKitEnabled }

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Group {
                if needsConnect {
                    ConnectView(status: authStatus)
                } else {
                    // Both stay mounted (crossfaded, not swapped) so switching tabs doesn't reset
                    // DayView's scroll position/selection every time — a plain `switch` here destroyed
                    // and recreated whichever view you left, which is what made this feel so jumpy.
                    ZStack {
                        AgendaView()
                            .opacity(tab == .agenda ? 1 : 0)
                            .allowsHitTesting(tab == .agenda)
                            .accessibilityHidden(tab != .agenda)
                        DayView(gridMode: $gridMode)
                            .opacity(tab == .day ? 1 : 0)
                            .allowsHitTesting(tab == .day)
                            .accessibilityHidden(tab != .day)
                    }
                    .animation(.easeInOut(duration: 0.2), value: tab)
                }
            }
            .navigationTitle(store.anchor.formatted(.dateTime.month(.abbreviated).day().year()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .navigationBarLeading) {
                    Menu {
                        Button { showCalendars = true } label: { Label("Calendars", systemImage: "calendar") }
                            .accessibilityIdentifier("calendarsButton")
                        Button { store.joinNextMeeting() } label: { Label("Join next meeting", systemImage: "video") }
                            .disabled(!store.hasNextMeeting)
                            .accessibilityIdentifier("joinNextButton")
                        Button { showSettings = true } label: { Label("Settings", systemImage: "gearshape") }
                            .accessibilityIdentifier("settingsButton")
                    } label: { Image(systemName: "line.3.horizontal") }
                    .accessibilityLabel("Menu").accessibilityIdentifier("menuButton")
                }
                ToolbarItem(placement: .principal) {
                    Picker("View", selection: $tab) {
                        ForEach(HomeTab.allCases) { Text($0.rawValue).tag($0) }
                    }
                    .pickerStyle(.segmented)
                    .frame(maxWidth: 200)
                    .accessibilityIdentifier("tabPicker")
                }
                ToolbarItem(placement: .primaryAction) {
                    Button { store.newDraft(start: defaultStart()) } label: { Image(systemName: "plus") }
                        .disabled(needsConnect).accessibilityLabel("New event").accessibilityIdentifier("addButton")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel(tab == .day && gridMode == .month ? "Previous month" : "Previous day").accessibilityIdentifier("prevButton")
                    Spacer()
                    Button("Today") { store.goToday() }.accessibilityIdentifier("todayButton")
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel(tab == .day && gridMode == .month ? "Next month" : "Next day").accessibilityIdentifier("nextButton")
                }
            }
        }
        .joinConfirmation()
        .sheet(isPresented: $showCalendars) { CalendarListSheet() }
        .sheet(isPresented: $showSettings) { SettingsSheet() }
        .onChange(of: store.eventKitEnabled) { _, _ in authStatus = EKEventStore.authorizationStatus(for: .event) }
        .onChange(of: store.errorMessage) { _, _ in authStatus = EKEventStore.authorizationStatus(for: .event) }
        .onReceive(NotificationCenter.default.publisher(for: UIApplication.didBecomeActiveNotification)) { _ in
            authStatus = EKEventStore.authorizationStatus(for: .event)
            if !store.eventKitEnabled && authStatus == .fullAccess { Task { await store.enableEventKit() } }
        }
        .sheet(item: $store.sheet) { sheet in
            switch sheet {
            case .detail(let ev):
                EventDetailSheet(event: ev).presentationDetents([.medium, .large])
            case .editor(let d):
                EventEditorSheet(draft: d).interactiveDismissDisabled()
            default:
                EmptyView()
            }
        }
    }

    /// Today: next half hour. Another day: 9 AM on the visible day.
    private func defaultStart() -> Date? {
        if store.cal.isDateInToday(store.anchor) { return nil }
        return store.cal.date(bySettingHour: 9, minute: 0, second: 0, of: store.anchor)
    }

    /// Day tab in Work Week/Week steps by week (via the shared store, which already knows how); every
    /// other case (Agenda, or Day tab showing a single day) steps by one day.
    private func shift(_ n: Int) {
        if tab == .day, gridMode != .day {
            store.step(n)
        } else {
            let d = store.cal.date(byAdding: .day, value: n, to: store.anchor) ?? store.anchor
            store.goTo(d)
        }
    }

}
