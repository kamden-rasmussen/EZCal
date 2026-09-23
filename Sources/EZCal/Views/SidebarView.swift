import SwiftUI

struct SidebarView: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        @Bindable var store = store

        ScrollView {
            VStack(alignment: .leading, spacing: 18) {
                MiniMonthView()

                ForEach(store.accounts) { acct in
                    group(acct.email) {
                        ReorderableSourceList(sources: store.ordered(store.calendars.filter { $0.accountId == acct.id }))
                    }
                }
                let apple = Dictionary(grouping: store.calendars.filter(\.isEventKit), by: \.accountId)
                ForEach(apple.keys.sorted(), id: \.self) { key in
                    group(apple[key]?.first?.groupTitle ?? key) {
                        ReorderableSourceList(sources: store.ordered(apple[key] ?? []))
                    }
                }

                let subscriptions = store.ordered(store.calendars.filter(\.isICS))
                if !subscriptions.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        SectionLabel("Subscribed").padding(.horizontal, 6).padding(.bottom, 4)
                        ReorderableSourceList(sources: subscriptions) { s in
                            SourceRow(source: s)
                                .contextMenu {
                                    if let sub = store.icsSubscriptions.first(where: { $0.source.id == s.id }) {
                                        Button("Remove", role: .destructive) { store.removeICSSubscription(sub) }
                                    }
                                }
                        }
                    }
                }
                addSubscriptionButton

                if store.tasks.enabled && !store.tasks.lists.isEmpty {
                    group("Tasks") {
                        ForEach(store.tasks.lists) { l in TaskListRow(list: l) }
                    }
                }

                if !store.accounts.isEmpty {
                    VStack(alignment: .leading, spacing: 2) {
                        HStack {
                            SectionLabel("Coworkers")
                            Spacer()
                            if !store.people.isEmpty {
                                let allOn = store.people.allSatisfy(store.isVisible)
                                Button(allOn ? "Hide all" : "Show all") { store.setPeopleVisible(!allOn) }
                                    .buttonStyle(.plain).font(.system(size: 11)).foregroundStyle(Theme.text3)
                            }
                        }
                        .padding(.horizontal, 6).padding(.bottom, 4)

                        ForEach(store.people) { p in
                            SourceRow(source: p, access: store.personAccess[p.id])
                                .contextMenu { Button("Remove", role: .destructive) { store.removePerson(p) } }
                        }

                        Button { store.showAddPerson = true } label: {
                            HStack(spacing: 9) {
                                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                                    .frame(width: 20, height: 20)
                                    .overlay(Circle().strokeBorder(Theme.text3, style: StrokeStyle(lineWidth: 1, dash: [2.5, 2])))
                                Text("Add coworker…")
                                Spacer()
                                KeyCap("P")
                            }
                            .foregroundStyle(Theme.text2)
                            .padding(.horizontal, 6).frame(height: 30)
                            .contentShape(Rectangle())
                        }
                        .buttonStyle(.plain)
                        .help("Add a coworker (P)")
                        .popover(isPresented: $store.showAddPerson, arrowEdge: .trailing) {
                            AddPersonView(isPresented: $store.showAddPerson)
                        }
                    }
                }
            }
            .padding(.horizontal, 14).padding(.top, 48).padding(.bottom, 14)
        }
        .background(Theme.side)
        .background(alignment: .top) { WindowDragArea().frame(height: 48) }
    }

    /// Small "Add calendar by URL…" affordance, styled like the "Add coworker…" row below it.
    private var addSubscriptionButton: some View {
        Button { store.openAddSubscription() } label: {
            HStack(spacing: 9) {
                Image(systemName: "plus").font(.system(size: 9, weight: .bold))
                    .frame(width: 20, height: 20)
                    .overlay(Circle().strokeBorder(Theme.text3, style: StrokeStyle(lineWidth: 1, dash: [2.5, 2])))
                Text("Add calendar by URL…")
                Spacer()
            }
            .foregroundStyle(Theme.text2)
            .padding(.horizontal, 6).frame(height: 30)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help("Subscribe to a read-only .ics feed")
    }

    private func group<C: View>(_ title: String, @ViewBuilder content: () -> C) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            SectionLabel(title).padding(.horizontal, 6).padding(.bottom, 4)
            content()
        }
    }
}

struct SectionLabel: View {
    let text: String
    init(_ text: String) { self.text = text }
    var body: some View {
        Text(text.uppercased())
            .font(.system(size: 11, weight: .semibold)).tracking(0.5)
            .foregroundStyle(Theme.text3)
            .lineLimit(1)
    }
}

/// A group of sidebar rows that can be drag-reordered among themselves (e.g. one Google account's
/// calendars, or the .ics subscriptions list). `sources` should already be in `store.ordered(...)`
/// order. `row` defaults to a plain `SourceRow` but can add its own modifiers (e.g. the subscriptions
/// list's "Remove" context menu) while keeping the same drag handling.
///
/// Reordering is done with a plain `DragGesture` rather than `.onDrag`/`.onDrop`: those go through
/// AppKit's system drag session, which on macOS both (a) never starts when the gesture originates on a
/// `Button` — its click gesture wins the mouse-down first — and (b) is unreliable inside a `ScrollView`,
/// which tends to claim the same mouse-drag for scrolling instead. A local `DragGesture` on our own grip
/// view sidesteps both: it's SwiftUI-only, has no AppKit drag session to fumble, and lives on a plain
/// `Image`, not the row's `Button`.
private struct ReorderableSourceList<RowContent: View>: View {
    @Environment(CalendarStore.self) private var store
    let sources: [Source]
    @ViewBuilder var row: (Source) -> RowContent
    @State private var draggingId: String?
    @State private var dragStartIndex: Int?
    @State private var dragOffset: CGFloat = 0
    @State private var hoveringId: String?

    /// `SourceRow`/`TaskListRow` are a fixed 30pt tall, in a `VStack(spacing: 2)` — see `group(_:)` in
    /// `SidebarView`. Used to turn a drag's vertical distance into "how many rows over".
    private let rowStep: CGFloat = 32

    init(sources: [Source], @ViewBuilder row: @escaping (Source) -> RowContent = { SourceRow(source: $0) }) {
        self.sources = sources
        self.row = row
    }

    var body: some View {
        ForEach(Array(sources.enumerated()), id: \.element.id) { index, s in
            HStack(spacing: 0) {
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.text3)
                    .frame(width: 16)
                    .opacity(hoveringId == s.id || draggingId == s.id ? 1 : 0)
                    .contentShape(Rectangle())
                    .gesture(dragGesture(for: s, index: index))
                row(s)
            }
            .onHover { hoveringId = $0 ? s.id : nil }
            .zIndex(draggingId == s.id ? 1 : 0)
            .shadow(color: .black.opacity(draggingId == s.id ? 0.25 : 0), radius: 6, y: 2)
            .offset(y: draggingId == s.id ? dragOffset : 0)
        }
    }

    private func dragGesture(for s: Source, index: Int) -> some Gesture {
        DragGesture(minimumDistance: 3, coordinateSpace: .local)
            .onChanged { value in
                if draggingId != s.id { draggingId = s.id; dragStartIndex = index }
                dragOffset = value.translation.height
            }
            .onEnded { value in
                defer { draggingId = nil; dragStartIndex = nil; dragOffset = 0 }
                guard let start = dragStartIndex else { return }
                let shift = Int((value.translation.height / rowStep).rounded())
                let target = min(max(start + shift, 0), sources.count - 1)
                if target != start {
                    withAnimation(.easeInOut(duration: 0.15)) {
                        store.moveCalendar(s.id, toIndex: target, within: sources)
                    }
                }
            }
    }
}

private struct SourceRow: View {
    @Environment(CalendarStore.self) private var store
    let source: Source
    var access: PersonAccess?
    @State private var hovering = false

    var body: some View {
        let on = store.isVisible(source)
        Button { store.toggle(source) } label: {
            HStack(spacing: 9) {
                if source.kind == .person {
                    Text(source.initials)
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(on ? Color.white : source.color)
                        .frame(width: 20, height: 20)
                        .background(Circle().fill(on ? source.color : Color.clear))
                        .overlay(Circle().strokeBorder(source.color, lineWidth: on ? 0 : 1.5))
                } else {
                    RoundedRectangle(cornerRadius: 4)
                        .fill(on ? source.color : Color.clear)
                        .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(source.color, lineWidth: on ? 0 : 1.5))
                        .overlay { if on { Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white) } }
                        .frame(width: 14, height: 14)
                        .padding(.horizontal, 3)
                }
                Text(source.name).lineLimit(1).foregroundStyle(on ? Theme.text : Theme.text2)
                Spacer(minLength: 0)
                switch access {
                case .busyOnly: Text("busy only").font(.system(size: 11)).foregroundStyle(Theme.text3)
                case .some(.none):
                    Image(systemName: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                        .help("This calendar isn't visible to you")
                default:
                    if let error = store.sourceErrors[source.id] {
                        Image(systemName: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange).help(error)
                    }
                }
            }
            .padding(.horizontal, 6).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(source.name), \(on ? "shown" : "hidden")")
        .accessibilityHint("Toggles this calendar")
    }
}

/// Sidebar row for a reminder list, styled to match `SourceRow` above.
private struct TaskListRow: View {
    @Environment(CalendarStore.self) private var store
    let list: TaskList
    @State private var hovering = false

    var body: some View {
        let on = store.tasks.isVisible(list)
        Button { store.tasks.toggle(list) } label: {
            HStack(spacing: 9) {
                RoundedRectangle(cornerRadius: 4)
                    .fill(on ? list.color : Color.clear)
                    .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(list.color, lineWidth: on ? 0 : 1.5))
                    .overlay { if on { Image(systemName: "checkmark").font(.system(size: 8, weight: .heavy)).foregroundStyle(.white) } }
                    .frame(width: 14, height: 14)
                    .padding(.horizontal, 3)
                Text(list.name).lineLimit(1).foregroundStyle(on ? Theme.text : Theme.text2)
                Spacer(minLength: 0)
            }
            .padding(.horizontal, 6).frame(height: 30)
            .background(RoundedRectangle(cornerRadius: 6).fill(hovering ? Theme.hover : .clear))
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .onHover { hovering = $0 }
        .accessibilityLabel("\(list.name) tasks, \(on ? "shown" : "hidden")")
        .accessibilityHint("Toggles this reminder list")
    }
}

struct AddPersonView: View {
    @Environment(CalendarStore.self) private var store
    @Binding var isPresented: Bool
    @State private var query = ""
    @State private var results: [DirectoryPerson] = []
    @State private var searching = false
    @FocusState private var focused: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            TextField("Search name or email…", text: $query)
                .textFieldStyle(.roundedBorder)
                .focused($focused)
                .onSubmit { addTyped() }
            if searching { ProgressView().controlSize(.small) }
            ForEach(results.filter { r in !store.people.contains { $0.calendarId == r.email.lowercased() } }) { p in
                Button { store.addPerson(p); isPresented = false } label: {
                    HStack {
                        Image(systemName: "person.crop.circle").foregroundStyle(Theme.text3)
                        VStack(alignment: .leading, spacing: 0) {
                            Text(p.name)
                            Text(p.email).font(.caption).foregroundStyle(Theme.text3)
                        }
                        Spacer()
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
            if looksLikeEmail {
                Button { addTyped() } label: { Label("Add \(query)", systemImage: "plus.circle") }
                    .buttonStyle(.plain)
            }
            if results.isEmpty && !searching && !looksLikeEmail {
                Text("Type two letters to search your organization, or a full email address. Return adds the first match.")
                    .font(.caption).foregroundStyle(Theme.text3)
            }
        }
        .padding(12)
        .frame(width: 300)
        .onAppear { focused = true }
        .task(id: query) {
            guard query.count >= 2 else { results = []; return }
            searching = true
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            results = await store.searchDirectory(query)
            searching = false
        }
    }

    private var looksLikeEmail: Bool { query.contains("@") && query.contains(".") }

    private func addTyped() {
        if let first = results.first, !looksLikeEmail { store.addPerson(first) }
        else if looksLikeEmail { store.addPerson(name: "", email: query) }
        isPresented = false
    }
}

struct MiniMonthView: View {
    @Environment(CalendarStore.self) private var store
    @State private var month = Date()

    var body: some View {
        // .everyMinute keeps "today" correct across a midnight rollover on a long-running window,
        // rather than relying on some unrelated re-render to happen to refresh it.
        TimelineView(.everyMinute) { _ in
            let c = store.cal
            let first = c.date(from: c.dateComponents([.year, .month], from: month))!
            let start = store.weekStart(first)
            let days = (0..<42).map { c.date(byAdding: .day, value: $0, to: start)! }
            let rows = c.isDate(days[35], equalTo: first, toGranularity: .month) ? 6 : 5
            let visible = Set(store.visibleDays.map { c.startOfDay(for: $0) })
            let cols = Array(repeating: GridItem(.flexible(), spacing: 0), count: 7)

            VStack(spacing: 6) {
                HStack {
                    Text(month.formatted(.dateTime.month(.wide).year())).font(.system(size: 13, weight: .semibold))
                    Spacer()
                    Button { month = c.date(byAdding: .month, value: -1, to: month)! } label: { Image(systemName: "chevron.left").font(.system(size: 11, weight: .semibold)) }
                        .buttonStyle(IconButtonStyle()).accessibilityLabel("Previous month")
                    Button { month = c.date(byAdding: .month, value: 1, to: month)! } label: { Image(systemName: "chevron.right").font(.system(size: 11, weight: .semibold)) }
                        .buttonStyle(IconButtonStyle()).accessibilityLabel("Next month")
                }
                .padding(.leading, 4)

                HStack(spacing: 0) {
                    ForEach(Array(days.prefix(7).enumerated()), id: \.offset) { _, d in
                        Text(d.formatted(.dateTime.weekday(.narrow))).font(.system(size: 11)).foregroundStyle(Theme.text3)
                            .frame(maxWidth: .infinity).frame(height: 18)
                    }
                }
                .accessibilityHidden(true)

                LazyVGrid(columns: cols, spacing: 2) {
                    ForEach(days.prefix(rows * 7), id: \.self) { d in
                        let today = c.isDateInToday(d)
                        let inMonth = c.isDate(d, equalTo: first, toGranularity: .month)
                        let sel = visible.contains(c.startOfDay(for: d))
                        Text(d.formatted(.dateTime.day()))
                            .font(.system(size: 11, weight: today ? .bold : .regular).monospacedDigit())
                            .foregroundStyle(today ? Theme.accentText : (inMonth ? Theme.text : Theme.text3))
                            .frame(width: 24, height: 24)
                            .background { if today { Circle().fill(Theme.accent) } }
                            .frame(maxWidth: .infinity).frame(height: 26)
                            .background { if sel && store.mode != .month { Theme.selection } }
                            .contentShape(Rectangle())
                            .onTapGesture { store.goTo(d) }
                            .accessibilityLabel(d.formatted(.dateTime.weekday(.wide).month(.wide).day()))
                            .accessibilityAddTraits(.isButton)
                    }
                }
            }
            .onChange(of: store.anchor) { _, new in
                if !c.isDate(new, equalTo: month, toGranularity: .month) { month = new }
            }
        }
    }
}
