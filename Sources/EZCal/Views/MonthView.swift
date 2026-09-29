import SwiftUI

/// Month view: a continuous vertical scroll of week rows (lazy), like scrolling a page.
///
/// Scroll position and `store.anchor` are kept in sync in both directions without feedback loops:
/// - user scroll -> `topWeek` -> `visibleKey` (cheap local state) -> debounced push to `store.anchor`
///   (which also schedules the debounced event reload). `lastPushedKey` lets us recognise the echo
///   of our own push when `store.anchor` changes.
/// - external anchor change (`[` / `]`, toolbar, Today, palette) -> animated programmatic scroll,
///   during which `programmatic` suppresses reading the moving scroll position back into the store.
struct MonthView: View {
    @Environment(CalendarStore.self) private var store

    @State private var window: WeekWindow?
    @State private var topWeek: Int?
    @State private var visibleKey: Int = 0
    @State private var lastPushedKey: Int = 0
    @State private var programmatic = false
    @State private var pushTask: Task<Void, Never>?
    @State private var settleTask: Task<Void, Never>?
    @State private var todayStart = Calendar.current.startOfDay(for: Date())

    var body: some View {
        let grid = MonthGrid(cal: store.cal)
        let win = window ?? WeekWindow(center: grid.firstWeek(ofMonth: grid.monthKey(of: store.anchor)))

        VStack(spacing: 0) {
            HStack(spacing: 0) {
                ForEach(0..<7, id: \.self) { col in
                    Text(grid.day(week: win.center, column: col).formatted(.dateTime.weekday(.abbreviated)).uppercased())
                        .font(.system(size: 11, weight: .medium)).tracking(0.5)
                        .foregroundStyle(Theme.text2)
                        .frame(maxWidth: .infinity).padding(.vertical, 8)
                }
            }
            Divider().overlay(Theme.line)
            GeometryReader { geo in
                let rowH: CGFloat = max(84, geo.size.height / 6)
                ScrollViewReader { proxy in
                    ScrollView(.vertical, showsIndicators: true) {
                        LazyVStack(spacing: 0) {
                            ForEach(win.range, id: \.self) { w in
                                MonthWeekRow(grid: grid, week: w, rowH: rowH, todayStart: todayStart)
                                    .frame(height: rowH)
                                    .id(w)
                            }
                        }
                        .scrollTargetLayout()
                    }
                    .scrollPosition(id: $topWeek, anchor: .top)
                    .onAppear {
                        let key = grid.monthKey(of: store.anchor)
                        visibleKey = key; lastPushedKey = key
                        window = win
                        scroll(proxy, toWeek: grid.firstWeek(ofMonth: key), animated: false)
                    }
                    .onChange(of: topWeek) { _, new in
                        guard !programmatic, let w = new else { return }
                        if let recentered = win.recentered(forTop: w) {
                            window = recentered
                            scroll(proxy, toWeek: w, animated: false)
                            return
                        }
                        let key = grid.monthKey(forWeek: w)
                        if key != visibleKey { visibleKey = key; schedulePush() }
                    }
                    .onChange(of: store.anchor) { _, anchor in
                        let key = grid.monthKey(of: anchor)
                        if key == visibleKey || key == lastPushedKey { return }   // our own echo
                        visibleKey = key; lastPushedKey = key
                        scroll(proxy, toWeek: grid.firstWeek(ofMonth: key), animated: true)
                    }
                    .onChange(of: grid.refStart) { _, _ in
                        // First-weekday setting changed: week indices shifted, so re-seat on the current month.
                        let w = grid.firstWeek(ofMonth: visibleKey)
                        window = WeekWindow(center: w)
                        scroll(proxy, toWeek: w, animated: false)
                    }
                }
            }
        }
        .background(Theme.bg)
        .task {
            // One cheap check a minute (instead of a TimelineView per cell) keeps "today" right across midnight.
            while !Task.isCancelled {
                try? await Task.sleep(nanoseconds: 60 * 1_000_000_000)
                let t = store.cal.startOfDay(for: Date())
                if t != todayStart { todayStart = t }
            }
        }
    }

    private func scroll(_ proxy: ScrollViewProxy, toWeek w: Int, animated: Bool) {
        programmatic = true
        if window?.range.contains(w) != true { window = WeekWindow(center: w) }
        DispatchQueue.main.async {
            if animated { withAnimation(.easeInOut(duration: 0.35)) { proxy.scrollTo(w, anchor: .top) } }
            else { proxy.scrollTo(w, anchor: .top) }
        }
        settleTask?.cancel()
        settleTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 700_000_000)
            guard !Task.isCancelled else { return }
            programmatic = false
            // Reconcile with wherever the scroll actually ended up.
            if let t = topWeek {
                let k = MonthGrid(cal: store.cal).monthKey(forWeek: t)
                if k != visibleKey { visibleKey = k; schedulePush() }
            }
        }
    }

    /// Debounced: only once scrolling pauses does the store learn the month changed (which reloads events).
    private func schedulePush() {
        pushTask?.cancel()
        pushTask = Task { @MainActor in
            try? await Task.sleep(nanoseconds: 150_000_000)
            guard !Task.isCancelled else { return }
            let g = MonthGrid(cal: store.cal)
            guard g.monthKey(of: store.anchor) != visibleKey else { return }
            lastPushedKey = visibleKey
            store.anchor = g.anchor(store.anchor, movedToMonth: visibleKey)
            store.scheduleReload()
        }
    }
}

private struct MonthWeekRow: View {
    let grid: MonthGrid
    let week: Int
    let rowH: CGFloat
    let todayStart: Date

    var body: some View {
        let maxItems = max(1, Int((rowH - 30) / 18))
        HStack(spacing: 0) {
            ForEach(0..<7, id: \.self) { col in
                let d = grid.day(week: week, column: col)
                MonthCell(day: d, monthKey: grid.monthKey(of: d), isToday: d == todayStart,
                          dayOfMonth: grid.cal.component(.day, from: d), maxItems: maxItems)
                    .frame(height: rowH)
                    .overlay(alignment: .leading) {
                        Rectangle().fill(Theme.line2).frame(width: 1)
                    }
            }
        }
        .overlay(alignment: .top) { Rectangle().fill(Theme.line2).frame(height: 1) }
    }
}

private struct MonthCell: View {
    @Environment(CalendarStore.self) private var store
    let day: Date
    let monthKey: Int
    let isToday: Bool
    let dayOfMonth: Int
    let maxItems: Int

    var body: some View {
        let evs = store.events(on: day)
        let all = evs.allDay + evs.timed
        let shown = all.prefix(all.count > maxItems ? maxItems - 1 : maxItems)
        let isFirstOfMonth = dayOfMonth == 1
        // Alternate shading by month, plus a month label on the 1st and a heavier rule along the
        // first week of each month, so it's always clear where one month ends and the next begins.
        let shade: Color = monthKey % 2 == 1 ? Theme.text3.opacity(0.07) : Color.clear

        VStack(alignment: .leading, spacing: 2) {
            Text(isFirstOfMonth ? day.formatted(.dateTime.month(.abbreviated).day()) : "\(dayOfMonth)")
                .font(.system(size: 12, weight: (isToday || isFirstOfMonth) ? .bold : .regular).monospacedDigit())
                .foregroundStyle(isToday ? Theme.accentText : Theme.text)
                .frame(minWidth: 22, minHeight: 22)
                .padding(.horizontal, isFirstOfMonth ? 4 : 0)
                .background(Capsule().fill(isToday ? Theme.accent : Color.clear))
            ForEach(Array(shown)) { e in
                let focused = store.focusedEventID == e.id
                HStack(spacing: 5) {
                    Circle().fill(e.color).frame(width: 6, height: 6)
                    Text(label(e)).font(.system(size: 11)).foregroundStyle(e.isOverlay ? Theme.text2 : Theme.text).lineLimit(1)
                    Spacer(minLength: 0)
                }
                .padding(.horizontal, 4).frame(height: 17)
                .background(RoundedRectangle(cornerRadius: 4).stroke(focused ? Theme.accent : Color.clear, lineWidth: 2))
                .contentShape(Rectangle())
                .onTapGesture { store.focusedEventID = e.id; store.sheet = .detail(e) }
                .accessibilityLabel(e.title)
                .accessibilityAddTraits(.isButton)
            }
            if all.count > shown.count {
                Text("\(all.count - shown.count) more").font(.system(size: 10)).foregroundStyle(Theme.text3).padding(.horizontal, 6)
            }
            Spacer(minLength: 0)
        }
        .padding(3)
        .frame(maxWidth: .infinity, alignment: .topLeading)
        .background(isToday ? Theme.todayBg : shade)
        .overlay(alignment: .top) {
            if dayOfMonth <= 7 { Rectangle().fill(Theme.text3.opacity(0.55)).frame(height: 1.5) }
        }
        .overlay(alignment: .leading) {
            if isFirstOfMonth { Rectangle().fill(Theme.text3.opacity(0.55)).frame(width: 1.5) }
        }
        .contentShape(Rectangle())
        .onTapGesture(count: 2) {
            // If the event-detail panel's open, this click just closes it instead of also creating an event.
            guard !store.isShowingDetail else { store.sheet = nil; return }
            let start = store.cal.date(bySettingHour: 9, minute: 0, second: 0, of: day)!
            store.newDraft(start: start)
        }
        .onTapGesture { store.anchor = day; store.setMode(.day) }
    }

    private func label(_ e: CalEvent) -> String {
        let t = e.isAllDay ? "" : e.start.formatted(.dateTime.hour().minute()) + " "
        let who = e.ownerName.map { "\($0) · " } ?? ""
        return t + who + e.title
    }
}
