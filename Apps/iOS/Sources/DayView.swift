import SwiftUI

/// Simple read-only vertical time grid for one day.
struct DayView: View {
    @Environment(CalendarStore.self) private var store
    private let hourHeight: CGFloat = 56
    private let gutter: CGFloat = 48

    var body: some View {
        let r = store.events(on: store.anchor)
        let day = store.cal.startOfDay(for: store.anchor)
        VStack(spacing: 0) {
            Text(store.anchor.formatted(.dateTime.weekday(.wide).month(.wide).day().year()))
                .font(.subheadline.weight(.semibold)).padding(.vertical, 6)
                .accessibilityIdentifier("dayTitle")
            Divider()
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
                                .gesture(LongPressGesture(minimumDuration: 0.5)
                                    .sequenced(before: DragGesture(minimumDistance: 0, coordinateSpace: .local))
                                    .onEnded { v in
                                        if case .second(true, let drag?) = v { createEvent(at: drag.location.y, day: day) }
                                    })
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
                            ForEach(layout(r.timed)) { item in
                                let e = item.event
                                let top = CGFloat(e.start.timeIntervalSince(day) / 3600) * hourHeight
                                let h = max(CGFloat(e.end.timeIntervalSince(e.start) / 3600) * hourHeight, 22)
                                let w = width / CGFloat(item.columns)
                                Button { store.sheet = .detail(e) } label: {
                                    VStack(alignment: .leading, spacing: 0) {
                                        Text(e.title).font(.caption.bold()).lineLimit(2)
                                        if h > 40 { Text(e.start.formatted(date: .omitted, time: .shortened)).font(.caption2) }
                                    }
                                    .padding(4)
                                    .frame(width: w - 2, height: h, alignment: .topLeading)
                                    .background(e.color.opacity(0.25), in: RoundedRectangle(cornerRadius: 6))
                                    .overlay(alignment: .leading) { Rectangle().fill(e.color).frame(width: 3) }
                                    .clipShape(RoundedRectangle(cornerRadius: 6))
                                }
                                .buttonStyle(.plain)
                                .accessibilityIdentifier("dayEvent")
                                .offset(x: gutter + w * CGFloat(item.column), y: max(top, 0))
                            }
                        }
                    }
                    .frame(height: hourHeight * 24 + 12)
                    .background(alignment: .top) {
                        // offset() doesn't move layout frames, so build the scroll anchor with real layout.
                        VStack(spacing: 0) {
                            Color.clear.frame(height: CGFloat(startHour(r.timed)) * hourHeight)
                            Color.clear.frame(height: 1).id("scroll")
                            Spacer(minLength: 0)
                        }
                    }
                    .padding(.top, 8)
                }
                // Fixed-height grid: cap type size so hour labels and short events don't clip.
                .dynamicTypeSize(...DynamicTypeSize.xLarge)
                .onAppear { proxy.scrollTo("scroll", anchor: .top) }
                .onChange(of: store.anchor) { _, _ in proxy.scrollTo("scroll", anchor: .top) }
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
