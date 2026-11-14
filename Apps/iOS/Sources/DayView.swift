import SwiftUI

/// Vertical time grid. Single-day (the default) supports touch drag/resize; Work Week and Week show
/// several read-only columns side by side, reusing the shared store's date math (`visibleDays`/`step`)
/// so paging and fetching behave exactly as they do on macOS.
struct DayView: View {
    @Environment(CalendarStore.self) private var store
    @Binding var gridMode: ViewMode
    // Shared with macOS: same UserDefaults key and range, so "zoom level" means the same thing on
    // both, though each platform's defaults are sandboxed separately (no cross-device sync).
    @AppStorage("hourHeight") private var hourHeightStorage: Double = 56
    private var hourHeight: CGFloat {
        CGFloat(min(max(hourHeightStorage, AppSettings.hourHeightRange.lowerBound), AppSettings.hourHeightRange.upperBound))
    }
    @AppStorage(WorkingHours.Keys.days) private var workDaysRaw = WorkingHours.defaultDaysRaw
    @AppStorage(WorkingHours.Keys.start) private var workStart = WorkingHours.standard.startMinute
    @AppStorage(WorkingHours.Keys.end) private var workEnd = WorkingHours.standard.endMinute
    private var workingHours: WorkingHours { WorkingHours(daysRaw: workDaysRaw, startMinute: workStart, endMinute: workEnd) }
    @State private var hourHeightAtPinchStart: Double?
    private let gutter: CGFloat = 48
    @State private var drag: DayDragState?
    @State private var selectedID: String?
    @State private var gridMinY: CGFloat = 0
    @State private var viewportH: CGFloat = 0
    @State private var saveError: String?
    @State private var showGoTo = false
    /// 3-day view is `gridMode == .day` plus this flag, so the shared `ViewMode` stays untouched.
    @AppStorage("gridThreeDay") private var threeDay = false
    /// Swiping the 3 Day / Work Week / Week grids moves one day instead of a whole page (macOS-style).
    @AppStorage(CalendarStore.weekSwipeByDayKey) private var swipeByDay = true
    // Swipe paging (#106).
    @State private var swipeX: CGFloat = 0
    @State private var swipeAxis: Axis?
    /// Set around a by-day swipe so the grid keeps its vertical scroll position instead of jumping back to the morning.
    @State private var keepScroll = false
    @AppStorage(HomeTab.showAgendaKey) private var showAgenda = true
    /// True while a released swipe is settling onto a day column; further swipes wait.
    @State private var settling = false
    /// Days drawn on each side of the visible window while swiping by day, so the grid can slide without blank edges.
    private static let stripPad = 7
    @State private var containerW: CGFloat = 390
    /// True from the moment a long press lifts an event (or a resize handle is grabbed) until it is dropped,
    /// so the page-swipe never fights an event drag.
    @State private var lifting = false
    /// Overlap layout (shared with macOS: same key/values — Side by side / Overlap (cascade) / Auto).
    @AppStorage("overlapLayoutMode") private var overlapLayoutModeRaw = OverlapLayoutMode.sideBySide.rawValue
    @AppStorage("sameTimeOrder") private var sameTimeOrderRaw = SameTimeOrder.startFirst.rawValue
    private var overlapMode: OverlapLayoutMode { OverlapLayoutMode(rawValue: overlapLayoutModeRaw) ?? .sideBySide }
    /// Stacked (same meeting on several calendars) card that was tapped, and the calendar picked from its list.
    @State private var stackSelection: StackSelection?
    @State private var pendingOpen: CalEvent?

    /// Pinch to zoom the grid's vertical density — touch pinch on iOS, same as trackpad pinch on macOS.
    private var pinchToZoomGesture: some Gesture {
        MagnificationGesture()
            .onChanged { scale in
                let base = hourHeightAtPinchStart ?? hourHeightStorage
                if hourHeightAtPinchStart == nil { hourHeightAtPinchStart = base }
                let range = AppSettings.hourHeightRange
                hourHeightStorage = min(max(base * scale, range.lowerBound), range.upperBound)
            }
            .onEnded { _ in hourHeightAtPinchStart = nil }
    }

    /// Days shown. Day mode ignores `store.mode` entirely (unaffected by whatever range was last
    /// fetched); Work Week/Week reuse the shared `visibleDays`, which `store.setMode` keeps in sync with.
    private var visibleDays: [Date] {
        if gridMode == .day {
            let d0 = store.cal.startOfDay(for: store.anchor)
            return threeDay ? (0..<3).compactMap { store.cal.date(byAdding: .day, value: $0, to: d0) } : [d0]
        }
        return store.visibleDays
    }

    /// 3 Day / Work Week / Week with "Swipe by day": the grid draws `stripPad` extra days either side and the finger
    /// slides that strip, settling on a whole day (Apple Calendar-style).
    private var stripMode: Bool { gridMode != .month && (isSingleDay || swipeByDay) }
    /// The one-day grid always slides day by day; the setting only decides whether the multi-day grids do.
    private var isSingleDay: Bool { gridMode == .day && !threeDay }
    /// Columns before the first visible one in what's drawn (0 outside strip mode).
    private var gridLead: Int { stripMode ? Self.stripPad : 0 }
    private var stripColWidth: CGFloat { max(stripColW(visibleDays.count), 1) }

    /// Most days one swipe may carry the grid: a screenful at most, and never past the pad drawn off-screen.
    private var maxStripDays: Int { min(Self.stripPad - 1, max(visibleDays.count, 1)) }

    /// The visible window plus `stripPad` days each side, skipping hidden weekend days like the grid does.
    private var stripDays: [Date] {
        let pad = Self.stripPad, cal = store.cal
        if gridMode == .day {
            let d0 = cal.startOfDay(for: store.anchor)
            return (-pad..<((threeDay ? 3 : 1) + pad)).compactMap { cal.date(byAdding: .day, value: $0, to: d0) }
        }
        let vis = visibleDays
        return WeekScrollMath.window(around: vis.first ?? store.anchor, before: pad, after: vis.count - 1 + pad,
                                     rule: store.weekColumns.rule, cal: cal)
    }

    /// Always a 3-letter month — screen space here is tighter than on macOS, which sometimes spells
    /// the month out in full (`store.title`).
    private var titleText: String {
        if gridMode == .month { return store.anchor.formatted(.dateTime.month(.wide).year()) }
        if gridMode == .day && !threeDay {
            return store.anchor.formatted(.dateTime.weekday(.abbreviated).month(.abbreviated).day().year())
        }
        let days = visibleDays
        guard let f = days.first, let l = days.last else { return "" }
        let sameMonth = store.cal.isDate(f, equalTo: l, toGranularity: .month)
        let sameYear = store.cal.isDate(f, equalTo: l, toGranularity: .year)
        let main = sameMonth
            ? "\(f.formatted(.dateTime.month(.abbreviated).day())) – \(l.formatted(.dateTime.day()))"
            : "\(f.formatted(.dateTime.month(.abbreviated).day())) – \(l.formatted(.dateTime.month(.abbreviated).day()))"
        return sameYear
            ? "\(main), \(f.formatted(.dateTime.year()))"
            : "\(main), \(f.formatted(.dateTime.year())) – \(l.formatted(.dateTime.year()))"
    }

    private var dayTitleButton: some View {
        Button { showGoTo = true } label: {
            Text(titleText).font(.subheadline.weight(.semibold))
        }
        .buttonStyle(.plain)
        .accessibilityIdentifier("dayTitle")
        .accessibilityHint("Opens a date picker")
    }

    var body: some View {
        let days = visibleDays
        VStack(spacing: 0) {
            HStack {
                // With Agenda hidden the top bar has no picker, so the date lives there instead (see `.toolbar` below).
                if showAgenda { dayTitleButton }
                Spacer()
                Picker("View", selection: gridChoice) {
                    Text("Day").tag(GridChoice.day)
                    Text("3 Day").tag(GridChoice.threeDay)
                    Text("Work Week").tag(GridChoice.workWeek)
                    Text("Week").tag(GridChoice.week)
                    Text("Month").tag(GridChoice.month)
                }
                .pickerStyle(.menu)
                .accessibilityIdentifier("gridModePicker")
                .onChange(of: gridMode) { _, _ in syncStore(); alignWeekIfNeeded(force: true) }
                .onChange(of: threeDay) { _, _ in syncStore() }
                .onChange(of: swipeByDay) { _, _ in syncStore(); store.goTo(store.anchor) }   // re-aligns the week to its start
                .onAppear { syncStore(); alignWeekIfNeeded(force: false) }
                .onDisappear { store.alignsLeadingToWeek = false }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            Divider()
            VStack(spacing: 0) {
                if gridMode == .month {
                    MonthView(gridMode: $gridMode)
                } else if days.count == 1 {
                    singleDay(stripMode ? stripDays : days, lead: gridLead)
                } else {
                    multiDay(stripMode ? stripDays : days, lead: gridLead, visible: days.count)
                }
            }
            .background(GeometryReader { g in
                Color.clear.onAppear { containerW = g.size.width }.onChange(of: g.size.width) { _, w in containerW = w }
            })
            .offset(x: stripMode ? 0 : swipeX)
            .opacity(stripMode ? 1 : 1 - min(abs(swipeX) / max(containerW, 1), 1) * 0.5)
            .clipped()
            .simultaneousGesture(swipeGesture)
        }
        .toolbar {
            if !showAgenda {
                ToolbarItem(placement: .principal) { dayTitleButton }
            }
        }
        .sheet(isPresented: $showGoTo) { GoToDateSheet() }
        .sheet(item: $stackSelection, onDismiss: {
            // Open the picked copy only after the list has finished dismissing (one sheet at a time).
            if let e = pendingOpen { pendingOpen = nil; store.sheet = .detail(e) }
        }) { sel in
            StackCalendarSheet(selection: sel) { pendingOpen = $0 }
        }
    }

    // MARK: - Grid choice (Day / 3 Day / Work Week / Week)

    enum GridChoice: Hashable { case day, threeDay, workWeek, week, month }

    private var gridChoice: Binding<GridChoice> {
        Binding(
            get: {
                switch gridMode {
                case .day: return threeDay ? .threeDay : .day
                case .workWeek: return .workWeek
                case .month: return .month
                default: return .week
                }
            },
            set: { c in
                switch c {
                case .day: threeDay = false; gridMode = .day
                case .threeDay: threeDay = true; gridMode = .day
                case .workWeek: threeDay = false; gridMode = .workWeek
                case .week: threeDay = false; gridMode = .week
                case .month: threeDay = false; gridMode = .month
                }
            })
    }

    /// Week / Work Week open on the week containing the anchor (like the old paged grid). On appear that only happens while
    /// the anchor is still the untouched default of today, so a day you've swiped to isn't snapped back.
    private func alignWeekIfNeeded(force: Bool) {
        guard stripMode, gridMode == .week || gridMode == .workWeek else { return }
        if force || store.cal.isDateInToday(store.anchor) { store.goTo(store.anchor) }
    }

    /// Keeps the shared store's fetch window in step with what the grid shows.
    private func syncStore() {
        store.fetchPadDays = stripMode ? 21 : 7   // strip mode draws ±7 days, so keep those loaded with room to spare
        store.extraFetchDays = gridMode == .day && threeDay ? 2 : 0
        store.alignsLeadingToWeek = gridMode == .week || gridMode == .workWeek
        if gridMode == .day { if threeDay { store.setMode(.day) } } else { store.setMode(gridMode) }
    }

    // MARK: - Swipe paging (#106)

    /// Horizontal swipe changes the day (Day) or the week (Work Week/Week). Only a clearly horizontal drag
    /// counts, and never while an event is lifted or the grid is being pinched, so scrolling, long-press
    /// drag and pinch-zoom keep working.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onChanged { v in
                guard !settling else { return }
                guard !lifting, drag == nil, hourHeightAtPinchStart == nil else { swipeX = 0; return }
                if swipeAxis == nil {
                    swipeAxis = abs(v.translation.width) > abs(v.translation.height) * 1.5 ? .horizontal : .vertical
                }
                guard swipeAxis == .horizontal else { return }
                if stripMode {
                    // The columns follow the finger, up to the extra days drawn off-screen.
                    let limit = CGFloat(maxStripDays) * stripColWidth
                    swipeX = min(max(v.translation.width, -limit), limit)
                } else {
                    swipeX = v.translation.width
                }
            }
            .onEnded { v in
                defer { swipeAxis = nil }
                guard !settling else { return }
                guard swipeAxis == .horizontal, !lifting, drag == nil else { settleSwipe(); return }
                let dx = v.translation.width, predicted = v.predictedEndTranslation.width
                if stripMode {
                    // Whole days the strip should end up moved by, counting a little momentum; dragging left = later days.
                    let n = min(max(Int((-predicted / stripColWidth).rounded()), -maxStripDays), maxStripDays)
                    settleStrip(by: n)
                } else if abs(dx) > containerW * 0.25 || abs(predicted) > containerW * 0.6 {
                    commitSwipe(dir: dx < 0 ? 1 : -1)
                } else {
                    settleSwipe()
                }
            }
    }

    /// Slides the strip the rest of the way onto day column `n` (0 = back to where it was), then moves the anchor by
    /// `n` days and zeroes the offset in one non-animated step: pixel-identical, so there is no visible jump.
    private func settleStrip(by n: Int) {
        let w = stripColWidth
        settling = true
        withAnimation(.easeOut(duration: 0.22)) { swipeX = -CGFloat(n) * w }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 240_000_000)
            var t = Transaction(); t.disablesAnimations = true
            withTransaction(t) {
                if n != 0 {
                    keepScroll = true
                    shiftAnchor(byDays: n)
                    // Cleared on a delay, not the next runloop turn: that can beat `onChange(of: store.anchor)`, which would
                    // then scroll to the new day's first event.
                    Task { @MainActor in
                        try? await Task.sleep(nanoseconds: 500_000_000)
                        keepScroll = false
                    }
                }
                swipeX = 0
            }
            settling = false
        }
    }

    /// Moves the leftmost day by `n` columns (Week / Work Week skip hidden weekend days).
    private func shiftAnchor(byDays n: Int) {
        if gridMode == .day {
            let d = store.cal.date(byAdding: .day, value: n, to: store.anchor) ?? store.anchor
            if threeDay { store.weekScrollAnchorChanged(to: d) } else { store.goTo(d) }
        } else {
            store.weekScrollAnchorChanged(to: WeekScrollMath.shift(store.anchor, byColumns: n, rule: store.weekColumns.rule, cal: store.cal))
        }
    }

    private func settleSwipe() { withAnimation(.easeOut(duration: 0.18)) { swipeX = 0 } }

    private func commitSwipe(dir: Int) {
        let w = containerW
        withAnimation(.easeIn(duration: 0.14)) { swipeX = -CGFloat(dir) * w }
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 140_000_000)
            navigate(dir)
            var t = Transaction(); t.animation = nil
            withTransaction(t) { swipeX = CGFloat(dir) * w * 0.5 }
            withAnimation(.easeOut(duration: 0.2)) { swipeX = 0 }
        }
    }

    /// One page forward/back for the current mode.
    private func navigate(_ n: Int) {
        if gridMode == .day {
            let step = threeDay && !swipeByDay ? 3 : 1
            store.goTo(store.cal.date(byAdding: .day, value: n * step, to: store.anchor) ?? store.anchor)
        } else if swipeByDay && gridMode != .month {
            // Week / Work Week: anchor is the leftmost column; move it one column (skipping hidden weekend days).
            let rule = store.weekColumns.rule
            store.weekScrollAnchorChanged(to: WeekScrollMath.shift(store.anchor, byColumns: n, rule: rule, cal: store.cal))
        } else { store.step(n) }
    }

    // MARK: - Day / multi-day headers (all-day rows)

    @ViewBuilder
    private func singleDay(_ days: [Date], lead: Int) -> some View {
        let allDay = days.map { store.events(on: $0).allDay }
        if !allDay[lead].isEmpty {
            stripRow(lead: lead, visible: 1) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, _ in
                    let pad = i != lead
                    VStack(spacing: 4) {
                        ForEach(allDay[i]) { ev in
                            Button { store.sheet = .detail(ev) } label: {
                                Text(ev.title).font(.footnote).lineLimit(1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .padding(6).background(ev.color.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                            }.buttonStyle(.plain)
                            .accessibilityIdentifier(pad ? "allDayEventPad" : "allDayEvent")
                        }
                    }
                    .frame(width: stripColW(1), alignment: .top)
                    .accessibilityHidden(pad)
                }
            }.padding(.vertical, 8)
            Divider()
        }
        timeGrid(days, lead: lead, visible: 1)
    }

    @ViewBuilder
    private func multiDay(_ days: [Date], lead: Int, visible: Int) -> some View {
        columnHeaders(days, lead: lead, visible: visible)
        Divider()
        let allDay = days.map { store.events(on: $0).allDay }
        // Only the visible window decides whether the all-day row shows, so it doesn't pop in mid-swipe.
        if allDay[lead..<(lead + visible)].contains(where: { !$0.isEmpty }) {
            stripRow(lead: lead, visible: visible) {
                ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                    VStack(alignment: .leading, spacing: 2) {
                        let shown = allDay[i].count > 2 ? 1 : allDay[i].count
                        ForEach(allDay[i].prefix(shown)) { ev in
                            Button { store.sheet = .detail(ev) } label: {
                                Text(ev.title).font(.system(size: 10)).lineLimit(1).minimumScaleFactor(0.8)
                                    .padding(.horizontal, 3).padding(.vertical, 1)
                                    .frame(maxWidth: .infinity, alignment: .leading)
                                    .background(ev.color.opacity(0.25), in: RoundedRectangle(cornerRadius: 3))
                            }.buttonStyle(.plain)
                            .accessibilityIdentifier(i < lead || i >= lead + visible ? "weekAllDayEventPad" : "weekAllDayEvent")
                        }
                        if allDay[i].count > 2 {
                            Text("+\(allDay[i].count - 1)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 3)
                                .accessibilityLabel("\(allDay[i].count - 1) more all-day events")
                                .accessibilityIdentifier(i < lead || i >= lead + visible ? "allDayMorePad" : "allDayMore")
                        }
                    }
                    .padding(.horizontal, 2).frame(width: stripColW(visible), alignment: .leading)
                    .accessibilityHidden(i < lead || i >= lead + visible)
                }
            }.padding(.vertical, 4)
            Divider()
        }
        timeGrid(days, lead: lead, visible: visible)
    }

    /// Width of one day column in the grid: the one-day grid keeps a small right margin.
    private func stripColW(_ visible: Int) -> CGFloat { (containerW - gutter - (visible == 1 ? 8 : 0)) / CGFloat(max(visible, 1)) }

    /// A row of per-day columns beside the hour gutter. Draws every day in `content` (columns `colW` wide) but shows
    /// only the visible window, offset so the first visible day sits at the gutter and sliding with `swipeX`.
    private func stripRow<Content: View>(lead: Int, visible: Int, @ViewBuilder _ content: () -> Content) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter, height: 1)
            HStack(spacing: 0) { content() }
                .offset(x: -CGFloat(lead) * stripColW(visible) + swipeX)
                .frame(width: stripColW(visible) * CGFloat(visible), alignment: .leading)
                .clipped()
        }
    }

    // MARK: - The time grid (one or more columns; touch drag/resize in all of them)

    private func timeGrid(_ days: [Date], lead: Int = 0, visible: Int? = nil) -> some View {
        let visible = visible ?? days.count
        let single = visible == 1
        let timedByDay = days.map { store.events(on: $0).timed }
        return ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { geo in
                    let colWidth = (geo.size.width - gutter - (single ? 8 : 0)) / CGFloat(visible)
                    ZStack(alignment: .topLeading) {
                        hourLabels()
                        // All days drawn side by side; the container is shifted so the first visible one sits at the gutter
                        // and slides with the finger, and masked so the off-screen days never show over the hour labels.
                        ZStack(alignment: .topLeading) {
                        ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                            let inWindow = i >= lead && i < lead + visible
                            Group {
                            // Long-press an empty spot to create an event there (events sit above and win).
                            Color.clear.contentShape(Rectangle())
                                .accessibilityIdentifier((single ? "dayGridBackground" : "weekDayGridBackground") + (inWindow ? "" : "Pad"))
                                .frame(width: colWidth, height: hourHeight * 24)
                                .offset(x: gutter + colWidth * CGFloat(i))
                                .onTapGesture { selectedID = nil }
                                .gesture(LongPressGesture(minimumDuration: 0.5)
                                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                                    .onEnded { v in
                                        if case .second(true, let drag?) = v { createEvent(at: drag.location.y, day: d) }
                                    })
                            // Wash over hours outside the working day (Settings -> Working hours).
                            ForEach(Array(workingHours.nonWorkingRanges(on: d, cal: store.cal).enumerated()), id: \.offset) { _, r in
                                Theme.nonWorkingShade
                                    .frame(width: colWidth, height: CGFloat(r.count) / 60 * hourHeight)
                                    .offset(x: gutter + colWidth * CGFloat(i), y: CGFloat(r.lowerBound) / 60 * hourHeight)
                                    .allowsHitTesting(false)
                                    .accessibilityHidden(true)
                            }
                            ForEach(EventLayout.place(timedByDay[i], day: d, cal: store.cal,
                                                                order: SameTimeOrder(rawValue: sameTimeOrderRaw) ?? .startFirst)) { item in
                                block(item, days: days, col: i, colWidth: colWidth, gridWidth: geo.size.width, inWindow: inWindow)
                            }
                            if store.cal.isDateInToday(d) {
                                NowIndicator(day: d, hourHeight: hourHeight, width: colWidth, cal: store.cal)
                                    .offset(x: gutter + colWidth * CGFloat(i)).zIndex(3)
                            }
                            }
                            .accessibilityHidden(!inWindow)
                            .allowsHitTesting(inWindow)
                        }
                        }
                        .offset(x: -CGFloat(lead) * colWidth + swipeX)
                        .frame(width: geo.size.width, height: hourHeight * 24, alignment: .topLeading)
                        .mask {
                            HStack(spacing: 0) {
                                Color.clear.frame(width: lead > 0 ? gutter : 0)
                                Color.black
                            }.padding(.vertical, -60)
                        }
                        if let d = drag, !d.committing {
                            timeLabel(d, days: days, lead: lead, colWidth: colWidth, gridWidth: geo.size.width)
                        }
                    }
                }
                .coordinateSpace(name: "grid")
                .background(GeometryReader { g in
                    Color.clear.preference(key: GridMinYKey.self, value: g.frame(in: .named("scroll")).minY)
                })
                .frame(height: hourHeight * 24 + 12)
                .background(alignment: .top) { scrollAnchors(timedByDay.flatMap { $0 }.sorted { $0.start < $1.start }) }
                .padding(.top, 8)
            }
            .coordinateSpace(name: "scroll")
            .refreshable { await store.refreshAll() }
            .gesture(pinchToZoomGesture)
            .background(GeometryReader { g in Color.clear.preference(key: ViewportHeightKey.self, value: g.size.height) })
            .onPreferenceChange(GridMinYKey.self) { gridMinY = $0 }
            .onPreferenceChange(ViewportHeightKey.self) { viewportH = $0 }
            .task(id: drag?.id) { await autoScroll(proxy) }
            .alert("Couldn’t move event", isPresented: Binding(get: { saveError != nil }, set: { if !$0 { saveError = nil } })) {
                Button("OK", role: .cancel) {}
            } message: { Text(saveError ?? "") }
            .confirmationDialog("Move recurring event", isPresented: Binding(
                get: { drag?.awaitingScope == true },
                set: { if !$0, drag?.awaitingScope == true, drag?.committing != true { drag = nil } }),
                titleVisibility: .visible) {
                ForEach(RecurrenceScope.allCases) { scope in
                    Button(scope.title) { commit(scope: scope) }
                }
                Button("Cancel", role: .cancel) { drag = nil }
            } message: { Text("This event repeats. Which events should the change affect?") }
            // Fixed-height grid: cap type size so hour labels and short events don't clip.
            .dynamicTypeSize(...(single ? DynamicTypeSize.xLarge : DynamicTypeSize.large))
            .onAppear { proxy.scrollTo("scroll", anchor: .top) }
            .onChange(of: store.anchor) { _, _ in
                if keepScroll { keepScroll = false } else { proxy.scrollTo("scroll", anchor: .top) }
            }
        }
    }

    @ViewBuilder
    private func scrollAnchors(_ timed: [CalEvent]) -> some View {
        // offset() doesn't move layout frames, so build the scroll anchor with real layout.
        VStack(spacing: 0) {
            Color.clear.frame(height: CGFloat(startHour(timed)) * hourHeight)
            Color.clear.frame(height: 1).id("scroll")
            Spacer(minLength: 0)
        }
        // 15-minute anchors: auto-scroll while dragging jumps between these.
        VStack(spacing: 0) {
            ForEach(0..<96, id: \.self) { i in Color.clear.frame(height: hourHeight / 4).id("a-\(i)") }
        }
    }

    private func hourLabels() -> some View {
        ForEach(0..<24, id: \.self) { h in
            HStack(alignment: .top, spacing: 4) {
                Text(hourLabel(h)).font(.caption2).foregroundStyle(.secondary)
                    .frame(width: gutter - 4, alignment: .trailing).offset(y: -6)
                Divider()
            }
            .frame(height: 1)
            .accessibilityElement(children: .combine)
            .accessibilityIdentifier("hour-\(h)")
            .offset(y: CGFloat(h) * hourHeight)
        }
    }

    private func columnHeaders(_ days: [Date], lead: Int, visible: Int) -> some View {
        stripRow(lead: lead, visible: visible) {
            ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                let today = store.cal.isDateInToday(d)
                VStack(spacing: 2) {
                    Text(d.formatted(.dateTime.weekday(.abbreviated))).font(.caption2).foregroundStyle(.secondary)
                    Text(d.formatted(.dateTime.day())).font(.subheadline.weight(today ? .bold : .regular))
                        .foregroundStyle(today ? Color.accentColor : .primary)
                }
                .frame(width: stripColW(visible))
                .accessibilityElement(children: .combine)
                .accessibilityIdentifier(i < lead || i >= lead + visible ? "columnHeaderPad" : "columnHeader")
                .accessibilityHidden(i < lead || i >= lead + visible)
            }
        }.padding(.vertical, 4)
    }

    // MARK: - Event blocks and touch drag

    private func canDrag(_ e: CalEvent) -> Bool { e.canEdit && !e.isOverlay && !e.isBusyOnly && !e.isICS && !e.isAllDay }

    private func timeText(_ s: Date, _ e: Date) -> String {
        "\(s.formatted(date: .omitted, time: .shortened)) – \(e.formatted(date: .omitted, time: .shortened))"
    }

    /// Where a placed event sits inside its column, per the overlap layout mode (same rules as macOS's
    /// `OverlapCluster`): real side-by-side slices, or a cascade of full-width cards each offset a little.
    private func geometry(_ p: PlacedEvent, colWidth: CGFloat) -> (w: CGFloat, x: CGFloat, y: CGFloat, cascaded: Bool) {
        if EventLayout.useSideBySide(sideSlots: p.sideSlots, availableWidth: colWidth, mode: overlapMode) {
            let slot = colWidth / CGFloat(p.sideSlots)
            return (slot, slot * CGFloat(p.sideSlot), 0, false)
        }
        let off = p.columns > 1 ? EventLayout.waterfallOffset(index: p.column, count: p.columns, dayWidth: colWidth) : 0
        let ny = p.columns > 1 ? EventLayout.waterfallYNudge(index: p.column) : 0
        return (max(colWidth - off, 24), off, ny, p.columns > 1)
    }

    @ViewBuilder
    private func block(_ item: PlacedEvent, days: [Date], col: Int, colWidth: CGFloat, gridWidth: CGFloat, inWindow: Bool = true) -> some View {
        let stack: [CalEvent]? = { if case .stack(let es) = item.item { return es } else { return nil } }()
        let e: CalEvent = { switch item.item { case .single(let e): return e; case .stack(let es): return es[0] } }()
        let single = days.count - 2 * gridLead == 1
        let live = drag?.id == e.id ? drag : nil
        // While moving across days the block is drawn in the column under the finger.
        let shownCol = min(max(col + (live?.kind == .move ? live?.dayDelta ?? 0 : 0), 0), days.count - 1)
        let day = days[col], shownDay = days[shownCol]
        let s = live?.start ?? item.item.start, en = live?.end ?? item.item.end
        let top = CGFloat(GridTime.y(of: s, on: shownDay, hourHeight: Double(hourHeight), cal: store.cal))
        let h = max(CGFloat(GridTime.height(from: s, to: en, hourHeight: Double(hourHeight), cal: store.cal)), single ? 22 : 20)
        let geo = geometry(item, colWidth: colWidth)
        let w = geo.w
        let narrow = w < 60
        let editable = canDrag(e)
        let selected = editable && selectedID == e.id
        let radius: CGFloat = single ? 6 : 4
        let label = stack.map { "\(e.title), on \($0.count) calendars" } ?? e.title
        let visual = Group {
            if let stack {
                StackedEventCard(events: stack, height: h, compact: narrow, single: single, live: live != nil, selected: selected)
                    .frame(width: w - 2, height: h, alignment: .topLeading)
            } else {
                singleVisual(e, s: s, h: h, w: w, narrow: narrow, single: single, radius: radius, live: live != nil, selected: selected)
            }
        }
        let body = visual
        .opacity(live?.valid == false ? 0.5 : 1)
        .shadow(color: .black.opacity(live == nil ? 0 : 0.3), radius: live == nil ? 0 : 8, y: 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(label)
        .accessibilityValue(timeText(s, en))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier((stack != nil ? (single ? "dayStackedEvent" : "weekStackedEvent") : (single ? "dayEvent" : "weekDayEvent")) + (inWindow ? "" : "Pad"))
        .onTapGesture {
            selectedID = nil
            if let stack { stackSelection = StackSelection(events: stack) } else { store.sheet = .detail(e) }
        }
        .overlay(alignment: .topTrailing) {
            if h >= 30 { JoinIconButton(event: e, compact: true).padding(3) }
        }

        Group {
            if editable {
                body
                    .gesture(LongPressGesture(minimumDuration: 0.4)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("grid")))
                        .onChanged { v in
                            guard case .second(true, let d) = v, drag == nil || drag?.id == e.id else { return }
                            lifting = true
                            if selectedID != e.id { selectedID = e.id; Haptics.impact() }
                            if let d {
                                if drag == nil { begin(e, .move, y: d.startLocation.y, day: day, col: col) }
                                move(to: d.location, days: days, colWidth: colWidth, gridWidth: gridWidth)
                            }
                        }
                        .onEnded { _ in lifting = false; finish() })
                    .overlay(alignment: .topTrailing) {
                        if selected { handle(e, .resizeTop, days: days, day: day, col: col, colWidth: colWidth, gridWidth: gridWidth).offset(x: 8, y: -12) }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if selected { handle(e, .resizeBottom, days: days, day: day, col: col, colWidth: colWidth, gridWidth: gridWidth).offset(x: 8, y: 12) }
                    }
            } else {
                body
            }
        }
        .zIndex(live != nil ? 10 : (selected ? 5 : Double(item.column) * 0.1))
        .scaleEffect(live != nil && live?.kind == .move ? 1.03 : 1)
        .offset(x: gutter + colWidth * CGFloat(shownCol) + geo.x, y: max(top, 0) + (geo.cascaded ? geo.y : 0))
    }

    private func singleVisual(_ e: CalEvent, s: Date, h: CGFloat, w: CGFloat, narrow: Bool, single: Bool,
                              radius: CGFloat, live: Bool, selected: Bool) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            (e.isPrivate && !e.isBusyOnly ? Text(Image(systemName: "lock.fill")) + Text(" ") + Text(e.title) : Text(e.title))
                .font(single ? .caption.bold() : .system(size: narrow ? 10 : 11, weight: .bold))
                .lineLimit(max(Int((h - 6) / (single ? 14 : 12)), 1)).minimumScaleFactor(single ? 1 : 0.85)
            if h > (single ? 40 : 34) && !narrow {
                Text(s.formatted(date: .omitted, time: .shortened))
                    .font(single ? .caption2 : .system(size: 9)).lineLimit(1).minimumScaleFactor(0.7)
            }
        }
        .padding(narrow ? 2 : (single ? 4 : 3))
        .frame(width: w - 2, height: h, alignment: .topLeading)
        .background(e.color.opacity(live ? 0.4 : 0.25), in: RoundedRectangle(cornerRadius: radius))
        .background(Color(.systemBackground), in: RoundedRectangle(cornerRadius: radius))
        .overlay(alignment: .leading) { Rectangle().fill(e.color).frame(width: single ? 3 : 2) }
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .overlay { if selected { RoundedRectangle(cornerRadius: radius).stroke(e.color, lineWidth: 2) } }
    }

    private func handle(_ e: CalEvent, _ kind: DayDragState.Kind, days: [Date], day: Date, col: Int,
                        colWidth: CGFloat, gridWidth: CGFloat) -> some View {
        ResizeHandle(color: e.color, id: kind == .resizeTop ? "resizeTop" : "resizeBottom")
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("grid"))
                .onChanged { v in
                    guard drag == nil || drag?.id == e.id else { return }
                    lifting = true
                    if drag == nil { begin(e, kind, y: v.startLocation.y, day: day, col: col); Haptics.impact() }
                    move(to: v.location, days: days, colWidth: colWidth, gridWidth: gridWidth)
                }
                .onEnded { _ in lifting = false; finish() })
    }

    private func timeLabel(_ d: DayDragState, days: [Date], lead: Int, colWidth: CGFloat, gridWidth: CGFloat) -> some View {
        let col = min(max(d.col0 + (d.kind == .move ? d.dayDelta : 0), 0), days.count - 1)
        let top = CGFloat(GridTime.y(of: d.start, on: days[col], hourHeight: Double(hourHeight), cal: store.cal))
        return Text(d.valid ? timeText(d.start, d.end) : "Release to cancel")
            .font(.caption.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.secondary.opacity(0.4)))
            .offset(x: max(min(gutter + colWidth * CGFloat(col - lead), gridWidth - 170), gutter), y: max(top - 28, 0))
            .zIndex(20)
            .allowsHitTesting(false)
            .accessibilityIdentifier("dragTimeLabel")
    }

    private func begin(_ e: CalEvent, _ kind: DayDragState.Kind, y: CGFloat, day: Date, col: Int) {
        drag = DayDragState(id: e.id, kind: kind, origStart: e.start, origEnd: e.end, startY: y, fingerY: y,
                            start: e.start, end: e.end, day: day, col0: col)
    }

    private func move(to p: CGPoint, days: [Date], colWidth: CGFloat, gridWidth: CGFloat) {
        guard var d = drag, !d.committing, !d.awaitingScope else { return }
        d.fingerY = p.y
        d.valid = p.y >= 0 && p.y <= hourHeight * 24 && p.x >= -8 && p.x <= gridWidth + 8
        if d.kind == .move, colWidth > 0 {
            // The finger's column within the visible window, as an index into the days actually drawn.
            let visibleCount = days.count - 2 * gridLead
            let c = min(max(Int(((p.x - gutter) / colWidth).rounded(.down)), 0), visibleCount - 1) + gridLead
            d.dayDelta = c - d.col0
            // Columns can skip days (hidden weekends), so the real move is the calendar days between the two columns.
            d.calendarDayDelta = store.cal.dateComponents([.day], from: days[d.col0], to: days[c]).day ?? d.dayDelta
        }
        recompute(&d)
        drag = d
    }

    private func recompute(_ d: inout DayDragState) {
        let r = DayDragMath.compute(kind: d.kind, origStart: d.origStart, origEnd: d.origEnd,
                                    deltaY: d.fingerY - d.startY, hourHeight: hourHeight, day: d.day, cal: store.cal,
                                    dayDelta: d.calendarDayDelta)
        if r.start != d.start || r.end != d.end { Haptics.tick() }
        d.start = r.start; d.end = r.end
    }

    /// Finger released: cancel, or commit (asking for the scope first when the event repeats).
    private func finish() {
        guard let d = drag, !d.committing, !d.awaitingScope else { return }
        guard d.valid, d.start != d.origStart || d.end != d.origEnd else { drag = nil; return }
        Haptics.impact()
        if store.displayEvents.first(where: { $0.id == d.id })?.isRecurring == true {
            drag?.awaitingScope = true
        } else {
            commit(scope: .thisEvent)
        }
    }

    private func commit(scope: RecurrenceScope) {
        guard var d = drag, let e = store.displayEvents.first(where: { $0.id == d.id }) else { drag = nil; return }
        d.awaitingScope = false; d.committing = true; drag = d
        var draft = EventDraft(existing: e, title: e.title, start: d.start, end: d.end, isAllDay: false,
                               sourceId: e.sourceId, location: e.location, notes: e.notes.strippingHTML,
                               attendees: e.attendees)
        draft.recurrenceScope = scope
        Task {
            do { try await store.save(draft) }
            catch { saveError = error.localizedDescription }
            drag = nil
        }
    }

    /// While a drag is active and the finger sits near the top/bottom edge, scroll the grid.
    private func autoScroll(_ proxy: ScrollViewProxy) async {
        while !Task.isCancelled, drag != nil {
            try? await Task.sleep(nanoseconds: 70_000_000)
            guard let d = drag, !d.committing, !d.awaitingScope, viewportH > 0 else { continue }
            let fingerViewport = d.fingerY + gridMinY
            let zone: CGFloat = 56
            let row = Int((-gridMinY + 8) / (hourHeight / 4))
            var target: Int?
            if fingerViewport < zone, gridMinY < 8 { target = max(row - 1, 0) }
            else if fingerViewport > viewportH - zone { target = min(row + 1, 95) }
            guard let t = target, t != row else { continue }
            let before = gridMinY
            proxy.scrollTo("a-\(t)", anchor: .top)
            try? await Task.sleep(nanoseconds: 20_000_000)
            // Content moved under a stationary finger: keep the finger's viewport position.
            if var cur = drag, gridMinY != before {
                cur.fingerY = fingerViewport - gridMinY
                recompute(&cur)
                drag = cur
            }
        }
    }

    /// New event at the pressed y position, rounded to 15 minutes, using the store's default duration.
    private func createEvent(at y: CGFloat, day: Date) {
        let minutes = Int((y / hourHeight * 60 / 15).rounded()) * 15
        let m = min(max(minutes, 0), 23 * 60 + 45)
        store.newDraft(start: GridTime.date(minutes: m, on: day, cal: store.cal))
    }

    /// Hour the grid scrolls to when it opens or the date changes; see `WorkingHours.initialScrollHour`.
    private func startHour(_ timed: [CalEvent]) -> Int {
        let today = visibleDays.contains(where: { store.cal.isDateInToday($0) })
        return workingHours.initialScrollHour(
            nowHour: today ? store.cal.component(.hour, from: Date()) : nil,
            firstEventHour: timed.first.map { store.cal.component(.hour, from: $0.start) })
    }

    private func hourLabel(_ h: Int) -> String {
        h == 0 ? "" : (Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date())!
            .formatted(.dateTime.hour()))
    }
}
