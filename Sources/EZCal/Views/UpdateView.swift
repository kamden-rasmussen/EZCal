import SwiftUI

/// "Check for Updates…" window: runs a manual check on open and shows the result, with the brew command
/// (and a copy button) when a newer release exists.
struct UpdateView: View {
    @Environment(UpdateChecker.self) private var updates
    @State private var copied = false

    var body: some View {
        VStack(alignment: .leading, spacing: 14) {
            switch updates.status {
            case .idle, .checking:
                HStack(spacing: 10) {
                    ProgressView().controlSize(.small)
                    Text("Checking for updates…").foregroundStyle(Theme.text2)
                }
            case .upToDate:
                Label("EZCal is up to date", systemImage: "checkmark.circle").font(.system(size: 15, weight: .semibold))
                Text("You have version \(updates.currentVersion?.description ?? "unknown").").foregroundStyle(Theme.text2)
            case .failed:
                Label("Couldn't check for updates", systemImage: "exclamationmark.triangle").font(.system(size: 15, weight: .semibold))
                Text("Check your connection and try again.").foregroundStyle(Theme.text2)
            case .available(let v):
                Label("EZCal \(v.description) is available", systemImage: "arrow.down.circle").font(.system(size: 15, weight: .semibold))
                Text("You have \(updates.currentVersion?.description ?? "an older version"). To update, run this in Terminal:")
                    .foregroundStyle(Theme.text2)
                HStack(spacing: 8) {
                    Text(UpdateChecker.upgradeCommand)
                        .font(.system(size: 12, design: .monospaced)).textSelection(.enabled)
                        .padding(.horizontal, 10).padding(.vertical, 7)
                        .frame(maxWidth: .infinity, alignment: .leading)
                        .background(RoundedRectangle(cornerRadius: 8).fill(Theme.surface))
                        .overlay(RoundedRectangle(cornerRadius: 8).stroke(Theme.line, lineWidth: 1))
                    Button {
                        Platform.copyToClipboard(UpdateChecker.upgradeCommand)
                        copied = true
                    } label: {
                        Image(systemName: copied ? "checkmark" : "doc.on.doc")
                    }
                    .buttonStyle(IconButtonStyle()).help("Copy command").accessibilityLabel("Copy command")
                }
            }
            HStack {
                Spacer()
                Button("Check Again") { copied = false; Task { await updates.check(manual: true) } }
                    .buttonStyle(SecondaryButtonStyle())
                    .disabled(updates.status == .checking)
            }
        }
        .padding(20)
        .frame(width: 420)
        .background(Theme.bg)
        .task { await updates.check(manual: true) }
    }
}

/// Toolbar pill shown only while a newer release is known; opens the update window.
struct UpdateIndicator: View {
    @Environment(UpdateChecker.self) private var updates
    @Environment(\.openWindow) private var openWindow

    var body: some View {
        if let v = updates.availableVersion {
            Button { openWindow(id: "update") } label: {
                Label("Update available", systemImage: "arrow.down.circle.fill")
                    .font(.system(size: 12, weight: .medium))
            }
            .buttonStyle(SecondaryButtonStyle())
            .help("EZCal \(v.description) is available")
        }
    }
}
