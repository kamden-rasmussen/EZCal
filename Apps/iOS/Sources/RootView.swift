import SwiftUI

enum HomeTab: String, CaseIterable, Identifiable {
    case agenda = "Agenda", day = "Day"
    var id: String { rawValue }
}

struct RootView: View {
    @Environment(CalendarStore.self) private var store
    @State private var tab: HomeTab = .agenda

    var body: some View {
        @Bindable var store = store
        NavigationStack {
            Group {
                switch tab {
                case .agenda: AgendaView()
                case .day: DayView()
                }
            }
            .navigationTitle(store.anchor.formatted(.dateTime.month(.wide).day().year()))
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
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
                        .accessibilityLabel("New event").accessibilityIdentifier("addButton")
                }
                ToolbarItemGroup(placement: .bottomBar) {
                    Button { shift(-1) } label: { Image(systemName: "chevron.left") }
                        .accessibilityLabel("Previous day").accessibilityIdentifier("prevButton")
                    Spacer()
                    Button("Today") { store.goToday() }.accessibilityIdentifier("todayButton")
                    Spacer()
                    Button { shift(1) } label: { Image(systemName: "chevron.right") }
                        .accessibilityLabel("Next day").accessibilityIdentifier("nextButton")
                }
            }
            .refreshable { await store.refreshAll() }
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

    private func shift(_ n: Int) {
        let d = store.cal.date(byAdding: .day, value: n, to: store.anchor) ?? store.anchor
        store.goTo(d)
    }

}
