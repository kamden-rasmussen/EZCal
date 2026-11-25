import SwiftUI

/// Shown when J finds several video meetings starting at the same time: pick which one to join (click, or press its number).
struct JoinChoiceDialog: View {
    let choices: [CalEvent]
    let onChoose: (CalEvent) -> Void
    let onCancel: () -> Void
    @FocusState private var focused: Bool

    var body: some View {
        ZStack {
            Color.black.opacity(0.32)
                .ignoresSafeArea()
                .onTapGesture(perform: onCancel)

            VStack(alignment: .leading, spacing: 14) {
                HStack(alignment: .top, spacing: 12) {
                    Image(systemName: "video")
                        .font(.system(size: 15, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 30, height: 30)
                        .background(Circle().fill(Theme.accent.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 4) {
                        Text("Which meeting?")
                            .font(.system(size: 15, weight: .semibold))
                            .foregroundStyle(Theme.text)
                        Text("More than one meeting starts at \(choices[0].start.formatted(date: .omitted, time: .shortened)).")
                            .font(.system(size: 13))
                            .foregroundStyle(Theme.text2)
                    }
                }

                VStack(spacing: 6) {
                    ForEach(Array(choices.prefix(9).enumerated()), id: \.element.id) { i, e in
                        Button { onChoose(e) } label: {
                            HStack(spacing: 8) {
                                KeyCap("\(i + 1)")
                                Circle().fill(e.color).frame(width: 8, height: 8)
                                Text(e.title).lineLimit(1)
                                Spacer(minLength: 0)
                            }
                            .frame(maxWidth: .infinity, alignment: .leading)
                        }
                        .buttonStyle(SecondaryButtonStyle())
                        .accessibilityIdentifier("joinChoice-\(i + 1)")
                    }
                }

                HStack(spacing: 4) { KeyCap("esc"); Text("cancel") }
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
            .onKeyPress(.escape) { onCancel(); return .handled }
            .onKeyPress { press in
                guard let n = Int(press.characters), (1...min(choices.count, 9)).contains(n) else { return .ignored }
                onChoose(choices[n - 1]); return .handled
            }
            .onAppear { focused = true }
        }
        .transition(.opacity)
    }
}
