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
        gridMode == .day ? [store.cal.startOfDay(for: store.anchor)] : store.visibleDays
    }

    /// Always a 3-letter month — screen space here is tighter than on macOS, which sometimes spells
    /// the month out in full (`store.title`).
    private var titleText: String {
        if gridMode == .day {
            return store.anchor.formatted(.dateTime.weekday(.wide).month(.abbreviated).day().year())
        }
        let days = store.visibleDays
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
                Text(titleText).font(.subheadline.weight(.semibold)).accessibilityIdentifier("dayTitle")
                Spacer()
                Picker("", selection: $gridMode) {
                    Text("Day").tag(ViewMode.day)
                    Text("Work Week").tag(ViewMode.workWeek)
                    Text("Week").tag(ViewMode.week)
                }
                .pickerStyle(.segmented)
                .frame(maxWidth: 260)
                .accessibilityIdentifier("gridModePicker")
                .onChange(of: gridMode) { _, m in if m != .day { store.setMode(m) } }
            }
            .padding(.horizontal, 8).padding(.vertical, 6)
            Divider()
            if days.count == 1 {
                singleDay(days[0])
            } else {
                multiDay(days)
            }
        }
    }

    // MARK: - Single day (touch drag/resize)

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
        ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { geo in
                    let width = geo.size.width - gutter - 8
                    ZStack(alignment: .topLeading) {
                        // Long-press an empty spot to create an event there (events sit above and win).
                        Color.clear.contentShape(Rectangle())
                            .accessibilityIdentifier("dayGridBackground")
                            .onTapGesture { selectedID = nil }
                            .gesture(LongPressGesture(minimumDuration: 0.5)
                                .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                                .onEnded { v in
                                    if case .second(true, let drag?) = v { createEvent(at: drag.location.y, day: day) }
                                })
                        hourLabels()
                        ForEach(layout(r.timed)) { item in
                            block(item, day: day, width: width, gridWidth: geo.size.width)
                        }
                        if let d = drag, !d.committing {
                            timeLabel(d, day: day)
                        }
                    }
                }
                .coordinateSpace(name: "grid")
                .background(GeometryReader { g in
                    Color.clear.preference(key: GridMinYKey.self, value: g.frame(in: .named("scroll")).minY)
                })
                .frame(height: hourHeight * 24 + 12)
                .background(alignment: .top) { scrollAnchors(r.timed) }
                .padding(.top, 8)
            }
            .coordinateSpace(name: "scroll")
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
            .dynamicTypeSize(...DynamicTypeSize.xLarge)
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

    // MARK: - Multi-day (Work Week / Week): read-only columns side by side

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
                        ForEach(allDay[i].prefix(2)) { ev in
                            Button { store.sheet = .detail(ev) } label: {
                                Text(ev.title).font(.caption2).lineLimit(1)
                                    .padding(.horizontal, 3).padding(.vertical, 1)
                                    .background(ev.color.opacity(0.25), in: RoundedRectangle(cornerRadius: 3))
                                    .frame(maxWidth: .infinity, alignment: .leading)
                            }.buttonStyle(.plain)
                        }
                    }.frame(maxWidth: .infinity, alignment: .leading).padding(.horizontal, 2)
                }
            }.padding(.vertical, 4)
            Divider()
        }
        let timedByDay = days.map { store.events(on: $0).timed }
        ScrollViewReader { proxy in
            ScrollView {
                GeometryReader { geo in
                    let colWidth = (geo.size.width - gutter) / CGFloat(days.count)
                    ZStack(alignment: .topLeading) {
                        hourLabels()
                        ForEach(Array(days.enumerated()), id: \.offset) { i, d in
                            Color.clear.contentShape(Rectangle())
                                .accessibilityIdentifier("weekDayGridBackground")
                                .frame(width: colWidth, height: hourHeight * 24)
                                .offset(x: gutter + colWidth * CGFloat(i))
                                .gesture(LongPressGesture(minimumDuration: 0.5)
                                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                                    .onEnded { v in
                                        if case .second(true, let drag?) = v { createEvent(at: drag.location.y, day: d) }
                                    })
                            ForEach(layout(timedByDay[i])) { item in
                                weekBlock(item, day: d, colIndex: i, colWidth: colWidth)
                            }
                        }
                    }
                }
                .frame(height: hourHeight * 24 + 12)
                .background(alignment: .top) { scrollAnchors(timedByDay.flatMap { $0 }.sorted { $0.start < $1.start }) }
                .padding(.top, 8)
            }
            .gesture(pinchToZoomGesture)
            .dynamicTypeSize(...DynamicTypeSize.large)
            .onAppear { proxy.scrollTo("scroll", anchor: .top) }
            .onChange(of: store.anchor) { _, _ in proxy.scrollTo("scroll", anchor: .top) }
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

    @ViewBuilder
    private func weekBlock(_ item: Placed, day: Date, colIndex: Int, colWidth: CGFloat) -> some View {
        let e = item.event
        let top = CGFloat(e.start.timeIntervalSince(day) / 3600) * hourHeight
        let h = max(CGFloat(e.end.timeIntervalSince(e.start) / 3600) * hourHeight, 20)
        let w = colWidth / CGFloat(item.columns)
        VStack(alignment: .leading, spacing: 0) {
            Text(e.title).font(.caption2.bold()).lineLimit(2)
            if h > 34 { Text(e.start.formatted(date: .omitted, time: .shortened)).font(.system(size: 9)) }
        }
        .padding(3)
        .frame(width: w - 2, height: h, alignment: .topLeading)
        .background(e.color.opacity(0.25), in: RoundedRectangle(cornerRadius: 4))
        .overlay(alignment: .leading) { Rectangle().fill(e.color).frame(width: 2) }
        .clipShape(RoundedRectangle(cornerRadius: 4))
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(e.title)
        .accessibilityIdentifier("weekDayEvent")
        .onTapGesture { store.sheet = .detail(e) }
        .offset(x: gutter + colWidth * CGFloat(colIndex) + w * CGFloat(item.column), y: max(top, 0))
    }

    // MARK: - Event blocks and touch drag (single-day only)

    private func canDrag(_ e: CalEvent) -> Bool { e.canEdit && !e.isOverlay && !e.isBusyOnly && !e.isICS && !e.isAllDay }

    private func timeText(_ s: Date, _ e: Date) -> String {
        "\(s.formatted(date: .omitted, time: .shortened)) – \(e.formatted(date: .omitted, time: .shortened))"
    }

    @ViewBuilder
    private func block(_ item: Placed, day: Date, width: CGFloat, gridWidth: CGFloat) -> some View {
        let e = item.event
        let live = drag?.id == e.id ? drag : nil
        let s = live?.start ?? e.start, en = live?.end ?? e.end
        let top = CGFloat(s.timeIntervalSince(day) / 3600) * hourHeight
        let h = max(CGFloat(en.timeIntervalSince(s) / 3600) * hourHeight, 22)
        let w = width / CGFloat(item.columns)
        let editable = canDrag(e)
        let selected = editable && selectedID == e.id
        let body = VStack(alignment: .leading, spacing: 0) {
            Text(e.title).font(.caption.bold()).lineLimit(2)
            if h > 40 { Text(s.formatted(date: .omitted, time: .shortened)).font(.caption2) }
        }
        .padding(4)
        .frame(width: w - 2, height: h, alignment: .topLeading)
        .background(e.color.opacity(live == nil ? 0.25 : 0.4), in: RoundedRectangle(cornerRadius: 6))
        .overlay(alignment: .leading) { Rectangle().fill(e.color).frame(width: 3) }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay { if selected { RoundedRectangle(cornerRadius: 6).stroke(e.color, lineWidth: 2) } }
        .opacity(live?.valid == false ? 0.5 : 1)
        .shadow(color: .black.opacity(live == nil ? 0 : 0.3), radius: live == nil ? 0 : 8, y: 3)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(e.title)
        .accessibilityValue(timeText(s, en))
        .accessibilityAddTraits(.isButton)
        .accessibilityIdentifier("dayEvent")
        .onTapGesture { selectedID = nil; store.sheet = .detail(e) }

        Group {
            if editable {
                body
                    .gesture(LongPressGesture(minimumDuration: 0.4)
                        .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .named("grid")))
                        .onChanged { v in
                            guard case .second(true, let d) = v, drag == nil || drag?.id == e.id else { return }
                            if selectedID != e.id { selectedID = e.id; Haptics.impact() }
                            if let d {
                                if drag == nil { begin(e, .move, y: d.startLocation.y) }
                                move(to: d.location, gridWidth: gridWidth, day: day)
                            }
                        }
                        .onEnded { _ in finish() })
                    .overlay(alignment: .topTrailing) {
                        if selected { handle(e, .resizeTop, day: day, gridWidth: gridWidth).offset(x: 8, y: -12) }
                    }
                    .overlay(alignment: .bottomTrailing) {
                        if selected { handle(e, .resizeBottom, day: day, gridWidth: gridWidth).offset(x: 8, y: 12) }
                    }
            } else {
                body
            }
        }
        .zIndex(live != nil ? 10 : (selected ? 5 : 0))
        .scaleEffect(live != nil && live?.kind == .move ? 1.03 : 1)
        .offset(x: gutter + w * CGFloat(item.column), y: max(top, 0))
    }

    private func handle(_ e: CalEvent, _ kind: DayDragState.Kind, day: Date, gridWidth: CGFloat) -> some View {
        ResizeHandle(color: e.color, id: kind == .resizeTop ? "resizeTop" : "resizeBottom")
            .gesture(DragGesture(minimumDistance: 0, coordinateSpace: .named("grid"))
                .onChanged { v in
                    guard drag == nil || drag?.id == e.id else { return }
                    if drag == nil { begin(e, kind, y: v.startLocation.y); Haptics.impact() }
                    move(to: v.location, gridWidth: gridWidth, day: day)
                }
                .onEnded { _ in finish() })
    }

    private func timeLabel(_ d: DayDragState, day: Date) -> some View {
        let top = CGFloat(d.start.timeIntervalSince(day) / 3600) * hourHeight
        return Text(d.valid ? timeText(d.start, d.end) : "Release to cancel")
            .font(.caption.weight(.semibold).monospacedDigit())
            .padding(.horizontal, 8).padding(.vertical, 4)
            .background(.thinMaterial, in: Capsule())
            .overlay(Capsule().stroke(.secondary.opacity(0.4)))
            .offset(x: gutter, y: max(top - 28, 0))
            .zIndex(20)
            .allowsHitTesting(false)
            .accessibilityIdentifier("dragTimeLabel")
    }

    private var dayStart: Date { store.cal.startOfDay(for: store.anchor) }

    private func begin(_ e: CalEvent, _ kind: DayDragState.Kind, y: CGFloat) {
        drag = DayDragState(id: e.id, kind: kind, origStart: e.start, origEnd: e.end, startY: y, fingerY: y,
                            start: e.start, end: e.end)
    }

    private func move(to p: CGPoint, gridWidth: CGFloat, day: Date) {
        guard var d = drag, !d.committing, !d.awaitingScope else { return }
        d.fingerY = p.y
        d.valid = p.y >= 0 && p.y <= hourHeight * 24 && p.x >= -8 && p.x <= gridWidth + 8
        recompute(&d, day: day)
        drag = d
    }

    private func recompute(_ d: inout DayDragState, day: Date) {
        let r = DayDragMath.compute(kind: d.kind, origStart: d.origStart, origEnd: d.origEnd,
                                    deltaY: d.fingerY - d.startY, hourHeight: hourHeight, day: day, cal: store.cal)
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
                recompute(&cur, day: dayStart)
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

    private func startHour(_ timed: [CalEvent]) -> Int {
        max((timed.first.map { store.cal.component(.hour, from: $0.start) } ?? 8) - 1, 0)
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
