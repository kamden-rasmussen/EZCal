import SwiftUI

/// Same meeting on several calendars (`EventGrouping`), drawn as ONE card with faint peeking edges behind it.
/// Visual only: `DayView` owns the tap/long-press/accessibility modifiers so a stack drags and reads like any
/// other event block.
struct StackedEventCard: View {
    let events: [CalEvent]   // 2+, same title/slot, different calendars
    let height: CGFloat
    var compact = false
    var single = true
    var live = false
    var selected = false

    private var front: CalEvent { events[0] }
    private var shape: RoundedRectangle { RoundedRectangle(cornerRadius: single ? 6 : 4) }
    private var showsPeek: Bool { height >= 30 }
    private var peekLayers: [CalEvent] { Array(events.dropFirst().prefix(2)) }

    var body: some View {
        ZStack(alignment: .topLeading) {
            if showsPeek {
                ForEach(Array(peekLayers.enumerated().reversed()), id: \.offset) { i, e in
                    let inset = CGFloat(i + 1) * 3
                    shape
                        .fill(Color(.systemBackground))
                        .overlay(shape.strokeBorder(e.color.opacity(0.6), lineWidth: 1.5))
                        .padding(EdgeInsets(top: inset, leading: inset, bottom: -inset, trailing: -inset))
                }
            }
            frontCard
                .padding(.trailing, showsPeek ? 6 : 0)
                .padding(.bottom, showsPeek ? 6 : 0)
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .opacity(events.allSatisfy(\.isDeclined) ? 0.5 : 1)
    }

    private var frontCard: some View {
        let c = front.color
        return VStack(alignment: .leading, spacing: 2) {
            Text(front.title)
                .font(single ? .caption.bold() : .system(size: compact ? 10 : 11, weight: .bold))
                .lineLimit(max(Int((height - 12) / (single ? 14 : 12)), 1))
                .minimumScaleFactor(single ? 1 : 0.85)
            HStack(spacing: 3) {
                ForEach(events.prefix(4)) { e in
                    Circle().fill(e.color).frame(width: 6, height: 6)
                }
                if events.count > 4 {
                    Text("+\(events.count - 4)").font(.system(size: 9, weight: .semibold)).foregroundStyle(.secondary)
                }
            }
            if height > 52 && !compact {
                Text("On \(events.count) calendars").font(.system(size: 10)).foregroundStyle(.secondary).lineLimit(1)
            }
            Spacer(minLength: 0)
        }
        .padding(compact ? 3 : 5)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background {
            ZStack { shape.fill(Color(.systemBackground)); shape.fill(c.opacity(live ? 0.4 : 0.25)) }
        }
        .overlay { shape.strokeBorder(c.opacity(0.6), lineWidth: 1.5) }
        .overlay { if selected { shape.inset(by: -1).strokeBorder(c, lineWidth: 2) } }
        .clipShape(shape)
    }
}

/// What the grid hands to `StackCalendarSheet` when a stacked card is tapped.
struct StackSelection: Identifiable {
    let events: [CalEvent]
    var id: String { events.map(\.id).sorted().joined(separator: "+") }
}

/// Lists the calendars one stacked meeting is on; picking a row opens that calendar's own copy of the event.
struct StackCalendarSheet: View {
    let selection: StackSelection
    let onPick: (CalEvent) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        NavigationStack {
            List {
                Section {
                    ForEach(selection.events) { e in
                        Button { onPick(e); dismiss() } label: {
                            HStack(spacing: 10) {
                                Circle().fill(e.color).frame(width: 10, height: 10)
                                Text(e.sourceName).foregroundStyle(.primary).lineLimit(1)
                                Spacer(minLength: 8)
                                Text("\(e.start.formatted(date: .omitted, time: .shortened)) – \(e.end.formatted(date: .omitted, time: .shortened))")
                                    .font(.caption).foregroundStyle(.secondary)
                            }
                            .contentShape(Rectangle())
                        }
                        .accessibilityIdentifier("stackCalendarRow")
                        .accessibilityLabel("\(e.sourceName), open event")
                    }
                } header: {
                    Text("On \(selection.events.count) calendars").accessibilityIdentifier("stackCalendarsHeader")
                }
            }
            .navigationTitle(selection.events[0].title)
            .navigationBarTitleDisplayMode(.inline)
            .toolbar { ToolbarItem(placement: .confirmationAction) { Button("Done") { dismiss() }.accessibilityIdentifier("stackDoneButton") } }
        }
        .presentationDetents([.medium])
        .accessibilityIdentifier("stackCalendarList")
    }
}
