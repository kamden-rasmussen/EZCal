import SwiftUI

extension CalendarStore {
    /// Same rule as the Mac's `joinMeetingDecision`: join directly from 10 minutes before the start
    /// through the end; any other time asks first (`joinRequest`, shown by `.joinConfirmation()`).
    func join(_ e: CalEvent) {
        guard let url = e.meetingURL else { errorMessage = "That event has no video link."; return }
        if e.isJoinable() { Platform.open(url) } else { joinRequest = e }
    }

    /// "Join next meeting": the next upcoming event that has a video link.
    func joinNextMeeting() {
        let candidates = CalEvent.joinCandidates(in: upcoming)
        guard let e = candidates.first else {
            errorMessage = "No upcoming meeting with a video link."
            return
        }
        if candidates.count > 1 { joinChoices = candidates } else { join(e) }
    }

    var hasNextMeeting: Bool { upcoming.contains { $0.end > Date() && $0.meetingURL != nil } }
}

/// Small video button for rows and grid blocks.
struct JoinIconButton: View {
    let event: CalEvent
    var compact = false
    @Environment(CalendarStore.self) private var store

    var body: some View {
        if event.meetingURL != nil, !event.isOverlay, !event.isBusyOnly {
            Button { store.join(event) } label: {
                Image(systemName: "video.fill")
                    .font(compact ? .caption2 : .subheadline)
                    .foregroundStyle(.white)
                    .padding(compact ? 4 : 7)
                    .background(event.color, in: Circle())
            }
            .buttonStyle(.plain)
            .accessibilityLabel("Join \(event.title)")
            .accessibilityIdentifier("joinButton")
        }
    }
}

struct JoinConfirmation: ViewModifier {
    @Environment(CalendarStore.self) private var store

    func body(content: Content) -> some View {
        @Bindable var store = store
        content.confirmationDialog(
            "Join “\(store.joinRequest?.title ?? "")”?",
            isPresented: Binding(get: { store.joinRequest != nil }, set: { if !$0 { store.joinRequest = nil } }),
            titleVisibility: .visible
        ) {
            Button("Join anyway") { store.confirmJoin(); store.joinRequest = nil }
            Button("Cancel", role: .cancel) { store.joinRequest = nil }
        } message: {
            if let e = store.joinRequest {
                Text("Scheduled for \(e.start.formatted(.dateTime.weekday(.wide).month(.wide).day().hour().minute())).")
            }
        }
    }
}

/// Asks which meeting to join when several video meetings start together.
struct JoinChoice: ViewModifier {
    @Environment(CalendarStore.self) private var store

    func body(content: Content) -> some View {
        content.confirmationDialog(
            "Which meeting?",
            isPresented: Binding(get: { store.joinChoices != nil }, set: { if !$0 { store.joinChoices = nil } }),
            titleVisibility: .visible
        ) {
            ForEach(store.joinChoices ?? []) { e in
                Button(e.title) { store.chooseJoin(e) }
            }
            Button("Cancel", role: .cancel) { store.joinChoices = nil }
        } message: {
            if let first = store.joinChoices?.first {
                Text("More than one meeting starts at \(first.start.formatted(date: .omitted, time: .shortened)).")
            }
        }
    }
}

extension View {
    func joinConfirmation() -> some View { modifier(JoinConfirmation()).modifier(JoinChoice()) }
}
