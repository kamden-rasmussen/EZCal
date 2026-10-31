import SwiftUI

/// Red "now" line with a dot, drawn across today's column and refreshed every minute (#108).
struct NowIndicator: View {
    let day: Date
    let hourHeight: CGFloat
    let width: CGFloat
    let cal: Calendar

    var body: some View {
        TimelineView(.everyMinute) { ctx in
            let c = cal.dateComponents([.hour, .minute], from: ctx.date)
            let minutes = (c.hour ?? 0) * 60 + (c.minute ?? 0)
            let y = CGFloat(minutes) / 60 * hourHeight
            ZStack(alignment: .leading) {
                Rectangle().fill(Color.red).frame(height: 1.5)
                Circle().fill(Color.red).frame(width: 9, height: 9).offset(x: -4)
            }
            .frame(width: width, height: 9, alignment: .leading)
            .offset(y: y - 4.5)
            .accessibilityElement(children: .ignore)
            .accessibilityLabel("Current time, \(ctx.date.formatted(date: .omitted, time: .shortened))")
            .accessibilityIdentifier("nowLine")
        }
        .allowsHitTesting(false)
    }
}
