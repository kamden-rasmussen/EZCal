import SwiftUI

/// Themed replacement for the system `confirmationDialog`: a dimmed scrim with a centered card that
/// uses the app's tokens. Return confirms, Esc (or clicking the scrim) cancels.
struct ConfirmDialog: View {
    let icon: String
    var destructive = false
    let title: String
    let message: String
    let confirmLabel: String
    let onConfirm: () -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 16) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: icon)
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(destructive ? Theme.now : Theme.accent)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill((destructive ? Theme.now : Theme.accent).opacity(0.12)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text(title)
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                            .lineLimit(2)
                        Text(message)
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text2)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                }

                HStack(spacing: 8) {
                    HStack(spacing: 4) { KeyCap("esc"); Text("cancel") }
                    Spacer()
                    Button("Cancel", action: onCancel).buttonStyle(SecondaryButtonStyle())
                    if destructive {
                        Button(confirmLabel, action: onConfirm).buttonStyle(DestructiveButtonStyle())
                    } else {
                        Button(confirmLabel, action: onConfirm).buttonStyle(PrimaryButtonStyle())
                    }
                }
                .font(.system(size: 11))
                .foregroundStyle(Theme.text3)
            }
            .padding(18)
            .frame(width: 380)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
            .focusable()
            .focusEffectDisabled()
            .focused($focused)
            .onKeyPress(.return) { onConfirm(); return .handled }
            .onKeyPress(.escape) { onCancel(); return .handled }
            .onAppear { focused = true }
        }
        .transition(.opacity)
    }
}
