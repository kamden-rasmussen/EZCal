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
        let now = Date()
        let candidates = upcoming.filter { $0.end > now && $0.meetingURL != nil }
        guard let e = CalEvent.nextMeeting(in: candidates, now: now) else {
            errorMessage = "No upcoming meeting with a video link."
            return
        }
        join(e)
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

extension View {
    func joinConfirmation() -> some View { modifier(JoinConfirmation()) }
}
