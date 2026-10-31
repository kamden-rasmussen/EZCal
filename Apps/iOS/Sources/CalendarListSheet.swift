import SwiftUI

/// Touch equivalent of the macOS sidebar: per-calendar visibility, color, order and subscriptions,
/// grouped by account. Uses the store's own `hidden` state, so it persists and filters Agenda/Day.
struct CalendarListSheet: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    @State private var showAdd = false
    @State private var colorTarget: Source?
    @State private var removeTarget: ICSSubscription?

    private var groups: [(title: String, items: [Source])] {
        var order: [String] = []
        var by: [String: [Source]] = [:]
        for s in store.ordered(store.calendars) {
            let t = s.isICS ? "Subscriptions" : s.groupTitle
            if by[t] == nil { order.append(t) }
            by[t, default: []].append(s)
        }
        return order.map { ($0, by[$0]!) }
    }

    private func subscription(for s: Source) -> ICSSubscription? {
        store.icsSubscriptions.first { $0.source.id == s.id }
    }

    private func setAll(visible: Bool) {
        for s in store.calendars where store.isVisible(s) != visible { store.toggle(s) }
    }

    var body: some View {
        NavigationStack {
            List {
                if !store.calendars.isEmpty {
                    Section {
                        HStack {
                            Button("Show all") { setAll(visible: true) }
                                .buttonStyle(.borderless).accessibilityIdentifier("showAllCalendars")
                            Spacer()
                            Button("Hide all") { setAll(visible: false) }
                                .buttonStyle(.borderless).accessibilityIdentifier("hideAllCalendars")
                        }
                    }
                }
                ForEach(groups, id: \.title) { g in
                    Section(g.title) {
                        ForEach(g.items) { s in row(s) }
                            .onMove { from, to in move(from, to, in: g.items) }
                    }
                }
                if groups.allSatisfy({ $0.title != "Subscriptions" }) {
                    Section("Subscriptions") {
                        Text("No subscribed calendars").foregroundStyle(.secondary)
                    }
                }
            }
            .overlay { if store.calendars.isEmpty && store.icsSubscriptions.isEmpty { ContentUnavailableView("No calendars", systemImage: "calendar") } }
            .navigationTitle("Calendars")
            .navigationBarTitleDisplayMode(.inline)
            .toolbar {
                ToolbarItem(placement: .cancellationAction) { EditButton().accessibilityIdentifier("reorderCalendarsButton") }
                ToolbarItem(placement: .primaryAction) {
                    Button { showAdd = true } label: { Image(systemName: "link.badge.plus") }
                        .accessibilityLabel("Add calendar by URL").accessibilityIdentifier("addSubscriptionButton")
                }
                ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("calendarsDoneButton") }
            }
            .sheet(isPresented: $showAdd) { AddSubscriptionSheet() }
            .sheet(item: $colorTarget) { s in
                ColorPickerSheet(source: s).presentationDetents([.height(300)])
            }
            .confirmationDialog("Remove subscription?", isPresented: Binding(get: { removeTarget != nil }, set: { if !$0 { removeTarget = nil } }),
                                presenting: removeTarget) { sub in
                Button("Remove \(sub.name)", role: .destructive) { store.removeICSSubscription(sub) }
                    .accessibilityIdentifier("confirmRemoveSubscription")
            }
        }
        .presentationDetents([.large])
    }

    @ViewBuilder private func row(_ s: Source) -> some View {
        HStack(spacing: 10) {
            Button { colorTarget = s } label: {
                Circle().fill(s.color).frame(width: 22, height: 22)
                    .overlay(Circle().strokeBorder(.secondary.opacity(0.4), lineWidth: 1))
                    .padding(4).contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .accessibilityLabel("Color for \(s.name)")
            .accessibilityIdentifier("calendarColor-\(s.name)")
            Toggle(isOn: Binding(get: { store.isVisible(s) }, set: { _ in store.toggle(s) })) {
                HStack(spacing: 6) {
                    Text(s.name)
                    if let err = store.sourceErrors[s.id] {
                        Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.orange).font(.caption)
                            .accessibilityLabel("Error: \(err)")
                    }
                }
            }
            .accessibilityIdentifier("calendarToggle-\(s.name)")
        }
        .swipeActions(edge: .trailing) {
            if let sub = subscription(for: s) {
                Button(role: .destructive) { removeTarget = sub } label: { Label("Remove", systemImage: "trash") }
                    .accessibilityIdentifier("removeSubscription-\(s.name)")
            }
        }
        .contextMenu {
            if let sub = subscription(for: s) {
                Button(role: .destructive) { removeTarget = sub } label: { Label("Remove subscription", systemImage: "trash") }
            }
        }
    }

    private func move(_ from: IndexSet, _ to: Int, in items: [Source]) {
        guard let i = from.first else { return }
        let dest = to > i ? to - 1 : to
        store.moveCalendar(items[i].id, toIndex: dest, within: items)
    }
}

/// Swatch grid with a checkmark on the current color and Reset for overridden calendars.
struct ColorPickerSheet: View {
    @Environment(CalendarStore.self) private var store
    @Environment(\.dismiss) private var dismiss
    let source: Source

    private var currentHex: String {
        store.calendars.first { $0.id == source.id }?.colorHex.uppercased() ?? source.colorHex.uppercased()
    }

    var body: some View {
        NavigationStack {
            VStack(spacing: 18) {
                LazyVGrid(columns: Array(repeating: GridItem(.flexible()), count: 5), spacing: 16) {
                    ForEach(Palette.people, id: \.self) { hex in
                        Button { store.setColor(hex, for: source) } label: {
                            Circle().fill(Color(hex: hex)).frame(width: 40, height: 40)
                                .overlay {
                                    if currentHex == hex.uppercased() {
                                        Image(systemName: "checkmark").font(.headline).foregroundStyle(.white)
                                    }
                                }
                        }
                        .buttonStyle(.plain)
                        .accessibilityLabel("Color \(hex)")
                        .accessibilityAddTraits(currentHex == hex.uppercased() ? .isSelected : [])
                        .accessibilityIdentifier("swatch-\(hex)")
                    }
                }
                if store.hasColorOverride(source) {
                    Button("Reset to default color") { store.resetColor(for: source) }
                        .accessibilityIdentifier("resetColorButton")
                }
                Spacer(minLength: 0)
            }
            .padding()
            .navigationTitle(source.name)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("colorDoneButton") } }
        }
    }
}
