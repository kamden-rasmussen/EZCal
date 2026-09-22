import SwiftUI

/// A due-dated task with no specific due time, shown in the all-day row next to `AllDayChip`s.
/// Tapping the checkbox toggles completion; there's no dedicated task editor yet (see README), so
/// editing anything else happens in Reminders.app.
struct TaskChip: View {
    @Environment(CalendarStore.self) private var store
    let task: EZTask

    var body: some View {
        Button { store.toggleTaskCompletion(task) } label: {
            HStack(spacing: 5) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 11))
                    .foregroundStyle(task.isCompleted ? task.color : Theme.text3)
                Text(task.title)
                    .font(.system(size: 12, weight: .medium))
                    .strikethrough(task.isCompleted)
                    .foregroundStyle(task.isCompleted ? Theme.text3 : Theme.text)
                    .lineLimit(1)
            }
            .padding(.horizontal, 7)
            .frame(maxWidth: .infinity, minHeight: 20, alignment: .leading)
            .background(RoundedRectangle(cornerRadius: 5).fill(task.color.opacity(0.12)))
            .overlay(RoundedRectangle(cornerRadius: 5).strokeBorder(task.color.opacity(0.4), style: StrokeStyle(lineWidth: 1, dash: [3, 2])))
        }
        .buttonStyle(.plain)
        .contentShape(RoundedRectangle(cornerRadius: 5))
        .help(task.isCompleted ? "Mark “\(task.title)” incomplete" : "Mark “\(task.title)” done")
        .accessibilityLabel("Task: \(task.title), \(task.isCompleted ? "completed" : "not completed")")
        .accessibilityAddTraits(.isButton)
    }
}

/// A due-dated task with a specific due time, positioned in `DayColumn` at that time like a small pill.
/// It doesn't participate in `EventLayout`'s overlap packing, so on a very busy hour it may sit on top
/// of an event block — acceptable for a first pass (see README known limitations).
struct TimedTaskMarker: View {
    @Environment(CalendarStore.self) private var store
    let task: EZTask

    var body: some View {
        Button { store.toggleTaskCompletion(task) } label: {
            HStack(spacing: 4) {
                Image(systemName: task.isCompleted ? "checkmark.circle.fill" : "circle")
                    .font(.system(size: 9))
                Text(task.title).font(.system(size: 10, weight: .medium)).lineLimit(1)
                if let due = task.dueDate {
                    Text(due.formatted(date: .omitted, time: .shortened)).font(.system(size: 9)).opacity(0.75)
                }
            }
            .strikethrough(task.isCompleted)
            .foregroundStyle(task.isCompleted ? Theme.text3 : task.color)
            .padding(.horizontal, 5).frame(height: 16)
            .background(Capsule().fill(Theme.surface).shadow(color: .black.opacity(0.12), radius: 1, y: 0.5))
            .overlay(Capsule().strokeBorder(task.color.opacity(0.6), lineWidth: 1))
        }
        .buttonStyle(.plain)
        .fixedSize()
        .help(task.title)
        .accessibilityLabel("Task: \(task.title), due \(task.dueDate?.formatted(date: .omitted, time: .shortened) ?? "")")
        .accessibilityAddTraits(.isButton)
    }
}
