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
    // Swipe paging (#106).
    @State private var swipeX: CGFloat = 0
    @State private var swipeAxis: Axis?
    @State private var containerW: CGFloat = 390
    /// True from the moment a long press lifts an event (or a resize handle is grabbed) until it is dropped,
    /// so the page-swipe never fights an event drag.
    @State private var lifting = false

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

    var body: some View {
        let days = visibleDays
        VStack(spacing: 0) {
            HStack {
                Button { showGoTo = true } label: {
                    Text(titleText).font(.subheadline.weight(.semibold))
                }
                .buttonStyle(.plain)
                .accessibilityIdentifier("dayTitle")
                .accessibilityHint("Opens a date picker")
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
                .onChange(of: gridMode) { _, _ in syncStore() }
                .onChange(of: threeDay) { _, _ in syncStore() }
                .onAppear { syncStore() }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            Divider()
            VStack(spacing: 0) {
                if gridMode == .month {
                    MonthView(gridMode: $gridMode)
                } else if days.count == 1 {
                    singleDay(days[0])
                } else {
                    multiDay(days)
                }
            }
            .background(GeometryReader { g in
                Color.clear.onAppear { containerW = g.size.width }.onChange(of: g.size.width) { _, w in containerW = w }
            })
            .offset(x: swipeX)
            .opacity(1 - min(abs(swipeX) / max(containerW, 1), 1) * 0.5)
            .clipped()
            .simultaneousGesture(swipeGesture)
        }
        .sheet(isPresented: $showGoTo) { GoToDateSheet() }
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

    /// Keeps the shared store's fetch window in step with what the grid shows.
    private func syncStore() {
        store.fetchPadDays = 7
        store.extraFetchDays = gridMode == .day && threeDay ? 2 : 0
        if gridMode == .day { if threeDay { store.setMode(.day) } } else { store.setMode(gridMode) }
    }

    // MARK: - Swipe paging (#106)

    /// Horizontal swipe changes the day (Day) or the week (Work Week/Week). Only a clearly horizontal drag
    /// counts, and never while an event is lifted or the grid is being pinched, so scrolling, long-press
    /// drag and pinch-zoom keep working.
    private var swipeGesture: some Gesture {
        DragGesture(minimumDistance: 20, coordinateSpace: .global)
            .onChanged { v in
                guard !lifting, drag == nil, hourHeightAtPinchStart == nil else { swipeX = 0; return }
                if swipeAxis == nil {
                    swipeAxis = abs(v.translation.width) > abs(v.translation.height) * 1.5 ? .horizontal : .vertical
                }
                if swipeAxis == .horizontal { swipeX = v.translation.width }
            }
            .onEnded { v in
                defer { swipeAxis = nil }
                guard swipeAxis == .horizontal, !lifting, drag == nil else { settleSwipe(); return }
                let dx = v.translation.width, predicted = v.predictedEndTranslation.width
                if abs(dx) > containerW * 0.25 || abs(predicted) > containerW * 0.6 {
                    commitSwipe(dir: dx < 0 ? 1 : -1)
                } else {
                    settleSwipe()
                }
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
            let step = threeDay ? 3 : 1
            store.goTo(store.cal.date(byAdding: .day, value: n * step, to: store.anchor) ?? store.anchor)
        } else { store.step(n) }
    }

    // MARK: - Day / multi-day headers (all-day rows)

    @ViewBuilder
    private func singleDay(_ day: Date) -> some View {
        let r = store.events(on: day)
        if !r.allDay.isEmpty {
            VStack(spacing: 4) {
                ForEach(r.allDay) { ev in
                    Button { store.sheet = .detail(ev) } label: {
                        Text(ev.title).font(.footnote).lineLimit(1)
                            .frame(maxWidth: .infinity, alignment: .leading)
                            .padding(6).background(ev.color.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                    }.buttonStyle(.plain)
                    .accessibilityIdentifier("allDayEvent")
                }
            }.padding(8)
            Divider()
        }
        timeGrid([day])
    }

    @ViewBuilder
    private func multiDay(_ days: [Date]) -> some View {
        columnHeaders(days)
        Divider()
        let allDay = days.map { store.events(on: $0).allDay }
        if allDay.contains(where: { !$0.isEmpty }) {
            HStack(spacing: 0) {
                Color.clear.frame(width: gutter, height: 1)
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
                            .accessibilityIdentifier("weekAllDayEvent")
                        }
                        if allDay[i].count > 2 {
                            Text("+\(allDay[i].count - 1)").font(.system(size: 10, weight: .semibold)).foregroundStyle(.secondary)
                                .padding(.horizontal, 3)
                                .accessibilityLabel("\(allDay[i].count - 1) more all-day events")
                                .accessibilityIdentifier("allDayMore")
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 2)
                }
            }.padding(.vertical, 4)
            Divider()
        }
        timeGrid(days)
    }

    // MARK: - The time grid (one or more columns; touch drag/resize in all of them)

    private func timeGrid(_ days: [Date]) -> some View {
        let single = days.count == 1
        let timedByDay = days.map { store.events(on: $0).timed }
        return ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { geo in
                    let colWidth = (geo.size.width - gutter - (single ? 8 : 0)) / CGFloat(days.count)
                    ZStack(alignment: .topLeading) {
                        hourLabels()
                        ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                            // Long-press an empty spot to create an event there (events sit above and win).
                            Color.clear.contentShape(Rectangle())
                                .accessibilityIdentifier(single ? "dayGridBackground" : "weekDayGridBackground")
                                .frame(width: colWidth, height: hourHeight * 24)
                                .offset(x: gutter + colWidth * CGFloat(i))
                                .onTapGesture { selectedID = nil }
                                .gesture(LongPressGesture(minimumDuration: 0.5)
                                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                                    .onEnded { v in
                                        if case .second(true, let drag?) = v { createEvent(at: drag.location.y, day: d) }
                                    })
                            ForEach(layout(timedByDay[i])) { item in
                                block(item, days: days, col: i, colWidth: colWidth, gridWidth: geo.size.width)
                            }
                            if store.cal.isDateInToday(d) {
                                NowIndicator(day: d, hourHeight: hourHeight, width: colWidth, cal: store.cal)
                                    .offset(x: gutter + colWidth * CGFloat(i)).zIndex(3)
                            }
                        }
                        if let d = drag, !d.committing {
                            timeLabel(d, days: days, colWidth: colWidth, gridWidth: geo.size.width)
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
            .onChange(of: store.anchor) { _, _ in proxy.scrollTo("scroll", anchor: .top) }
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

    private func columnHeaders(_ days: [Date]) -> some View {
        HStack(spacing: 0) {
            Color.clear.frame(width: gutter, height: 1)
            ForEach(days, id: \.self) { d in
                let today = store.cal.isDateInToday(d)
                VStack(spacing: 2) {
                    Text(d.formatted(.dateTime.weekday(.abbreviated))).font(.caption2).foregroundStyle(.secondary)
                    Text(d.formatted(.dateTime.day())).font(.subheadline.weight(today ? .bold : .regular))
                        .foregroundStyle(today ? Color.accentColor : .primary)
                }.frame(maxWidth: .infinity)
            }
        }.padding(.vertical, 4)
    }

    // MARK: - Event blocks and touch drag

    private func canDrag(_ e: CalEvent) -> Bool { e.canEdit && !e.isOverlay && !e.isBusyOnly && !e.isICS && !e.isAllDay }

    private func timeText(_ s: Date, _ e: Date) -> String {
        "\(s.formatted(date: .omitted, time: .shortened)) – \(e.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder
    private func block(_ item: Placed, days: [Date], col: Int, colWidth: CGFloat, gridWidth: CGFloat) -> some View {
        let e = item.event
        let single = days.count == 1
        let live = drag?.id == e.id ? drag : nil
        // While moving across days the block is drawn in the column under the finger.
        let shownCol = min(max(col + (live?.kind == .move ? live?.dayDelta ?? 0 : 0), 0), days.count - 1)
        let day = days[col], shownDay = days[shownCol]
        let s = live?.start ?? e.start, en = live?.end ?? e.end
        let top = CGFloat(s.timeIntervalSince(shownDay) / 3600) * hourHeight
        let h = max(CGFloat(en.timeIntervalSince(s) / 3600) * hourHeight, single ? 22 : 20)
        let w = colWidth / CGFloat(item.columns)
        let narrow = w < 60
        let editable = canDrag(e)
        let selected = editable && selectedID == e.id
        let radius: CGFloat = single ? 6 : 4
        let body = VStack(alignment: .leading, spacing: 0) {
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
        .background(e.color.opacity(live == nil ? 0.25 : 0.4), in: RoundedRectangle(cornerRadius: radius))
        .overlay(alignment: .leading) { Rectangle().fill(e.color).frame(width: single ? 3 : 2) }
        .clipShape(RoundedRectangle(cornerRadius: radius))
        .overlay { if selected { RoundedRectangle(cornerRadius: radius).stroke(e.color, lineWidth: 2) } }
        .opacity(live?.valid == false ? 0.5 : 1)
        .shadow(color: .black.opacity(live == nil ? 0 : 0.3), radius: live == nil ? 0 : 8, y: 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(e.title)
        .accessibilityValue(timeText(s, en))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier(single ? "dayEvent" : "weekDayEvent")
        .onTapGesture { selectedID = nil; store.sheet = .detail(e) }
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
        .zIndex(live != nil ? 10 : (selected ? 5 : 0))
        .scaleEffect(live != nil && live?.kind == .move ? 1.03 : 1)
        .offset(x: gutter + colWidth * CGFloat(shownCol) + w * CGFloat(item.column), y: max(top, 0))
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

    private func timeLabel(_ d: DayDragState, days: [Date], colWidth: CGFloat, gridWidth: CGFloat) -> some View {
        let col = min(max(d.col0 + (d.kind == .move ? d.dayDelta : 0), 0), days.count - 1)
        let top = CGFloat(d.start.timeIntervalSince(days[col]) / 3600) * hourHeight
        return Text(d.valid ? timeText(d.start, d.end) : "Release to cancel")
            .font(.caption.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.secondary.opacity(0.4)))
            .offset(x: max(min(gutter + colWidth * CGFloat(col), gridWidth - 170), gutter), y: max(top - 28, 0))
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
            let c = min(max(Int(((p.x - gutter) / colWidth).rounded(.down)), 0), days.count - 1)
            d.dayDelta = c - d.col0
        }
        recompute(&d)
        drag = d
    }

    private func recompute(_ d: inout DayDragState) {
        let r = DayDragMath.compute(kind: d.kind, origStart: d.origStart, origEnd: d.origEnd,
                                    deltaY: d.fingerY - d.startY, hourHeight: hourHeight, day: d.day, cal: store.cal,
                                    dayDelta: d.dayDelta)
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
        guard let start = store.cal.date(byAdding: .minute, value: m, to: day) else { return }
        store.newDraft(start: start)
    }

    /// Hour the grid scrolls to when it opens or the date changes: a little before "now" when today is
    /// showing, otherwise an hour before the first event (8 on an empty day).
    private func startHour(_ timed: [CalEvent]) -> Int {
        if visibleDays.contains(where: { store.cal.isDateInToday($0) }) {
            return max(store.cal.component(.hour, from: Date()) - 2, 0)
        }
        return max((timed.first.map { store.cal.component(.hour, from: $0.start) } ?? 8) - 1, 0)
    }

    private func hourLabel(_ h: Int) -> String {
        h == 0 ? "" : (Calendar.current.date(bySettingHour: h, minute: 0, second: 0, of: Date())!
            .formatted(.dateTime.hour()))
    }

    struct Placed: Identifiable { let event: CalEvent; let column: Int; let columns: Int; var id: String { event.id } }

    /// Greedy column packing for overlapping events.
    private func layout(_ events: [CalEvent]) -> [Placed] {
        var out: [Placed] = []
        var cluster: [(CalEvent, Int)] = []
        var colEnds: [Date] = []
        func flush() {
            let n = max(colEnds.count, 1)
            out += cluster.map { Placed(event: $0.0, column: $0.1, columns: n) }
            cluster = []; colEnds = []
        }
        for e in events {
            if let maxEnd = colEnds.max(), e.start >= maxEnd { flush() }
            if let i = colEnds.firstIndex(where: { $0 <= e.start }) {
                colEnds[i] = e.end; cluster.append((e, i))
            } else {
                colEnds.append(e.end); cluster.append((e, colEnds.count - 1))
            }
        }
        flush()
        return out
    }
}
