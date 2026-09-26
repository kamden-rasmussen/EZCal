import SwiftUI

/// Pure math behind `ReorderableSourceList`'s live drag preview — split out (rather than left as a
/// private method on that view) so it's directly unit-testable without any SwiftUI view inspection.
enum SidebarReorder {
    /// How many row-steps a row NOT being dragged should shift, given the dragged row's original index
    /// `start` and its live "if you let go now" landing index `target` (both within the same array,
    /// `CalendarStore.moveCalendar(_:toIndex:within:)`'s "final index" meaning). The rows strictly
    /// between `start` and `target` shift by one row's worth of space to close/open the gap — everything
    /// else, including `index == start` itself, doesn't move.
    static func rowShift(for index: Int, start: Int, target: Int) -> Int {
        if start < target { return (index > start && index <= target) ? -1 : 0 }
        if start > target { return (index >= target && index < start) ? 1 : 0 }
        return 0
    }
}

struct SidebarView: View {
    @Environment(CalendarStore.self) private var store

    var body: some View {
        @Bindable var store = store

        VStack(spacing: 0) {
            // Fixed strip behind the traffic lights so scrolled content never slides underneath them.
            Theme.side.frame(height: 56).overlay { WindowDragArea() }
                .overlay(alignment: .bottom) {
                    // Etched edge: a soft shadow line with a white highlight just beneath it.
                    VStack(spacing: 0) {
                        Rectangle().fill(Theme.line2).frame(height: 1)
                        Rectangle().fill(Theme.highlight).frame(height: 1)
                    }
                    .offset(y: 2)
                }
                .zIndex(1)

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
                            SourceRow(source: p, access: store.personAccess[p.id], isTemporary: store.temporaryPeople.contains(p.id))
                                .contextMenu {
                                    if store.temporaryPeople.contains(p.id) {
                                        Button("Keep permanently") { store.makePersonPermanent(p) }
                                    }
                                    Button("Remove", role: .destructive) { store.removePerson(p) }
                                }
                        }

                        Button { store.requestAddPerson() } label: {
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
                        .help("P to peek at a coworker's calendar for this session (Esc clears peeks), ⇧P to add them for good")
                    }
                }
            }
            .padding(.horizontal, 14).padding(.top, 4).padding(.bottom, 14)
            }
        }
        .background(Theme.side)
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
/// which tends to claim the same mouse-drag for scrolling instead. A local `DragGesture` has no AppKit
/// drag session to fumble, sidestepping (b) — but (a) still applies to a plain `.gesture()`, which takes
/// exclusive priority over a view's own gesture recognizers and would swallow the row's `Button` clicks
/// entirely. `.simultaneousGesture()` instead runs alongside the `Button`: a plain click (no meaningful
/// movement) still toggles the calendar, since the drag never exceeds `minimumDistance` and the click
/// recognizes normally; a real drag exceeds it and takes over, which also cancels the `Button`'s own
/// press so a drag never *also* fires a toggle. Attaching it to the whole row (not just a small handle)
/// is what lets a drag start from anywhere on the row, not only a narrow sliver — the previous
/// grip-only version was hard to reliably grab.
///
/// While dragging, the dragged row floats and follows the cursor 1:1 (`dragOffset`, unanimated — any
/// animation there would make it visibly lag behind the pointer); everything else is driven off
/// `previewTarget`, the row's current live "if you let go now" landing slot: the rows between its old and
/// new position slide out of the way (`rowShift`), and an accent line (`lineAboveId`/`lineBelowLastId`)
/// marks exactly where it'll land. None of that touches the store — only `dragGesture`'s `onEnded` calls
/// `store.moveCalendar`, once, so letting go back where you started (or canceling) never writes.
private struct ReorderableSourceList<RowContent: View>: View {
    @Environment(CalendarStore.self) private var store
    let sources: [Source]
    @ViewBuilder var row: (Source) -> RowContent
    @State private var draggingId: String?
    @State private var dragStartIndex: Int?
    @State private var dragOffset: CGFloat = 0
    /// Where the dragged row would land if released right now — index into `sources` (0...count-1),
    /// same "final position" meaning as `CalendarStore.moveCalendar(_:toIndex:within:)` expects. Updated
    /// live as the drag crosses a row boundary; only actually committed to the store on drop, so a
    /// canceled drag (or just dragging around and letting go back where it started) never writes.
    @State private var previewTarget: Int?
    @State private var hoveringId: String?

    /// `SourceRow`/`TaskListRow` are a fixed 30pt tall, in a `VStack(spacing: 2)` — see `group(_:)` in
    /// `SidebarView`. Used to turn a drag's vertical distance into "how many rows over".
    private let rowStep: CGFloat = 32

    init(sources: [Source], @ViewBuilder row: @escaping (Source) -> RowContent = { SourceRow(source: $0) }) {
        self.sources = sources
        self.row = row
    }

    /// `sources` with the row currently being dragged lifted out — i.e. the order the *other* rows are
    /// already in, which is what `previewTarget` indexes into for the insertion line.
    private var others: [Source] {
        guard let draggingId else { return sources }
        return sources.filter { $0.id != draggingId }
    }
    /// The line renders directly above this row (target lands before it).
    private var lineAboveId: String? {
        guard let target = previewTarget, target < others.count else { return nil }
        return others[target].id
    }
    /// Only used for "drop at the very end": the line renders below the last row instead.
    private var lineBelowLastId: String? {
        guard let target = previewTarget, target == others.count else { return nil }
        return others.last?.id
    }

    var body: some View {
        ForEach(Array(sources.enumerated()), id: \.element.id) { index, s in
            HStack(spacing: 0) {
                // Purely a visual hint that the row can be dragged — the draggable area is the whole
                // row (see `.simultaneousGesture` below), not just this icon.
                Image(systemName: "line.3.horizontal")
                    .font(.system(size: 10, weight: .semibold))
                    .foregroundStyle(Theme.text3)
                    .frame(width: 16)
                    .opacity(hoveringId == s.id || draggingId == s.id ? 1 : 0)
                row(s)
            }
            .contentShape(Rectangle())
            .onHover { hoveringId = $0 ? s.id : nil }
            .overlay(alignment: .top) {
                if lineAboveId == s.id { insertionLine }
            }
            .overlay(alignment: .bottom) {
                if lineBelowLastId == s.id { insertionLine }
            }
            .zIndex(draggingId == s.id ? 1 : 0)
            .shadow(color: .black.opacity(draggingId == s.id ? 0.25 : 0), radius: 6, y: 2)
            .offset(y: draggingId == s.id ? dragOffset : rowShift(for: index))
            .simultaneousGesture(dragGesture(for: s, index: index))
        }
    }

    private var insertionLine: some View {
        Capsule().fill(Theme.accent).frame(height: 2).padding(.horizontal, 4).offset(y: -1)
            .allowsHitTesting(false)
    }

    /// How far a row NOT being dragged should slide to make room, given where the dragged row currently
    /// previews landing — the rows strictly between its old and new slot shift by one row's worth of
    /// space to close/open the gap, exactly like a card physically sliding past them.
    private func rowShift(for index: Int) -> CGFloat {
        guard let start = dragStartIndex, let target = previewTarget else { return 0 }
        return CGFloat(SidebarReorder.rowShift(for: index, start: start, target: target)) * rowStep
    }

    private func dragGesture(for s: Source, index: Int) -> some Gesture {
        DragGesture(minimumDistance: 5, coordinateSpace: .local)
            .onChanged { value in
                if draggingId != s.id { draggingId = s.id; dragStartIndex = index; previewTarget = index }
                dragOffset = value.translation.height
                guard let start = dragStartIndex else { return }
                let shift = Int((value.translation.height / rowStep).rounded())
                let newTarget = min(max(start + shift, 0), sources.count - 1)
                if newTarget != previewTarget {
                    withAnimation(.interactiveSpring(response: 0.25, dampingFraction: 0.8)) {
                        previewTarget = newTarget
                    }
                }
            }
            .onEnded { _ in
                defer { draggingId = nil; dragStartIndex = nil; dragOffset = 0; previewTarget = nil }
                guard let start = dragStartIndex, let target = previewTarget, target != start else { return }
                withAnimation(.easeInOut(duration: 0.15)) {
                    store.moveCalendar(s.id, toIndex: target, within: sources)
                }
            }
    }
}

private struct SourceRow: View {
    @Environment(CalendarStore.self) private var store
    let source: Source
    var access: PersonAccess?
    var isTemporary = false
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
                if isTemporary {
                    Image(systemName: "clock").font(.system(size: 9)).foregroundStyle(Theme.text3)
                        .help("Just for this session — right-click to keep permanently")
                }
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
