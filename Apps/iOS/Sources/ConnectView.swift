import SwiftUI
import EventKit

/// First-run / denied state shown instead of Agenda/Day until calendar access is granted.
struct ConnectView: View {
    @Environment(CalendarStore.self) private var store
    let status: EKAuthorizationStatus

    private var blocked: Bool { status == .denied || status == .restricted || status == .writeOnly }

    var body: some View {
        VStack(spacing: 16) {
            Image(systemName: blocked ? "lock.slash" : "calendar.badge.plus")
                .font(.system(size: 56)).foregroundStyle(.tint)
            Text(blocked ? "Calendar access is off" : "Connect your calendars")
                .font(.title2.bold()).multilineTextAlignment(.center)
            Text(blocked
                 ? "EZCal needs full access to Calendars to show and edit your events. Turn it on in Settings."
                 : "EZCal shows and edits the calendars already on this iPhone, such as iCloud, or your Google Calendar.")
                .font(.body).foregroundStyle(.secondary).multilineTextAlignment(.center)
            if blocked {
                Button("Open Settings") {
                    if let url = URL(string: UIApplication.openSettingsURLString) { UIApplication.shared.open(url) }
                }
                .buttonStyle(.borderedProminent).controlSize(.large)
                .accessibilityIdentifier("openSettingsButton")
            } else {
                Button("Connect calendars") { Task { await store.enableEventKit() } }
                    .buttonStyle(.borderedProminent).controlSize(.large)
                    .accessibilityIdentifier("connectButton")
            }
            Button {
                Task { await store.signIn() }
            } label: {
                Label(store.isSigningIn ? "Waiting for browser…" : "Sign in with Google", systemImage: "person.badge.plus")
            }
            .buttonStyle(.bordered).controlSize(.large)
            .disabled(store.isSigningIn || !AppSettings.hasGoogleCredentials)
            .accessibilityIdentifier("connectGoogleButton")
            if !AppSettings.hasGoogleCredentials {
                Text("Google sign-in isn't configured in this build.")
                    .font(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            if let m = store.errorMessage, !blocked {
                Text(m).font(.footnote).foregroundStyle(.red).multilineTextAlignment(.center)
            }
        }
        .padding(32)
        .frame(maxWidth: 420, maxHeight: .infinity)
        .accessibilityIdentifier("connectView")
    }
}
