import SwiftUI
import UIKit

/// Transient state for a touch drag (move or resize) of an event in the Day view. Never persisted.
struct DayDragState {
    enum Kind { case move, resizeTop, resizeBottom }
    var id: String
    var kind: Kind
    var origStart: Date
    var origEnd: Date
    var startY: CGFloat          // finger y (grid content space) when the drag began
    var fingerY: CGFloat         // latest finger y (grid content space)
    var start: Date
    var end: Date
    var valid = true             // false when the finger is outside the grid: releasing cancels
    var awaitingScope = false    // released on a recurring event; waiting for the scope dialog
    var committing = false       // save in flight; the preview stays until it finishes
    var day: Date = Date()       // start of the day the event was dragged from
    var col0 = 0                 // grid column the drag began in
    var dayDelta = 0             // columns moved sideways (move only)
}

/// Pure time math for touch dragging; reuses the shared `EventDragMath` for snapping/moving/bottom resize.
enum DayDragMath {
    static let minimumMinutes = 15

    static func compute(kind: DayDragState.Kind, origStart: Date, origEnd: Date, deltaY: CGFloat,
                        hourHeight: CGFloat, day: Date, cal: Calendar,
                        dayDelta: Int = 0) -> (start: Date, end: Date) {
        let delta = EventDragMath.snap(minutes: Double(deltaY / hourHeight * 60))
        let dayEnd = cal.date(byAdding: .day, value: 1, to: day) ?? day.addingTimeInterval(86400)
        switch kind {
        case .move:
            var d = delta
            if origStart >= day, origEnd <= dayEnd {   // keep events that fit in the day inside it
                let lo = -Int(GridTime.minutes(of: origStart, on: day, cal: cal))
                let hi = 1440 - Int(GridTime.minutes(of: origEnd, on: day, cal: cal).rounded(.up))
                d = min(max(d, lo), hi)
            }
            return EventDragMath.moved(start: origStart, end: origEnd, minutesDelta: d, dayDelta: dayDelta, cal: cal)
        case .resizeBottom:
            var r = EventDragMath.resized(start: origStart, end: origEnd, minutesDelta: delta,
                                          minimumMinutes: minimumMinutes, cal: cal)
            if r.end > dayEnd { r.end = max(dayEnd, origStart.addingTimeInterval(Double(minimumMinutes) * 60)) }
            return r
        case .resizeTop:
            let latest = GridTime.shifted(origEnd, byWallMinutes: -minimumMinutes, cal: cal)
            var s = GridTime.shifted(origStart, byWallMinutes: delta, cal: cal)
            s = min(s, latest)
            if origStart >= day { s = max(s, day) }
            return (s, origEnd)
        }
    }
}

struct GridMinYKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}
struct ViewportHeightKey: PreferenceKey {
    static var defaultValue: CGFloat = 0
    static func reduce(value: inout CGFloat, nextValue: () -> CGFloat) { value = nextValue() }
}

/// Small pill shown at a block's edge while it is selected; dragging it resizes the event.
struct ResizeHandle: View {
    let color: Color
    let id: String
    var body: some View {
        ZStack {
            Color.clear
            Capsule().fill(.background).overlay(Capsule().stroke(color, lineWidth: 2))
                .frame(width: 28, height: 10)
        }
        .frame(width: 56, height: 24)
        .contentShape(Rectangle())
        .accessibilityElement(children: .ignore)
        .accessibilityLabel("Resize")
        .accessibilityIdentifier(id)
    }
}

@MainActor
enum Haptics {
    static func impact() { UIImpactFeedbackGenerator(style: .light).impactOccurred() }
    static func tick() { UISelectionFeedbackGenerator().selectionChanged() }
}
