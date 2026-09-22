import SwiftUI

/// Asked before editing or deleting an occurrence of a recurring event (issue #3).
/// Fully keyboard-operable: ↑/↓ + Return to pick the highlighted row, or 1/2/3 to jump straight to one.
struct RecurrenceScopeView: View {
    @Environment(CalendarStore.self) private var store
    let event: CalEvent
    let action: RecurrenceAction
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var options: [RecurrenceScope] { RecurrenceScope.allCases }

    var body: some View {
        VStack(alignment: .leading, spacing: 16) {
            HStack(alignment: .top, spacing: 10) {
                Image(systemName: "repeat").font(.system(size: 15)).foregroundStyle(Theme.text3).padding(.top, 2)
                VStack(alignment: .leading, spacing: 3) {
                    Text("\(action.noun) recurring event").font(.system(size: 16, weight: .semibold))
                    Text("“\(event.title)” repeats. Which events should this affect?")
                        .font(.system(size: 13)).foregroundStyle(Theme.text2)
                }
            }

            VStack(spacing: 4) {
                ForEach(Array(options.enumerated()), id: \.offset) { i, scope in
                    row(scope, index: i)
                        .onTapGesture { choose(i) }
                }
            }

            HStack(spacing: 16) {
                hint("↑↓", "choose"); hint("1-3", "jump"); hint("↩", action.noun.lowercased()); hint("esc", "cancel")
                Spacer()
            }
            .font(.system(size: 11)).foregroundStyle(Theme.text3)

            HStack {
                Button { store.sheet = nil } label: { Text("Cancel") }
                    .buttonStyle(SecondaryButtonStyle()).keyboardShortcut(.cancelAction)
                Spacer()
                Button { choose(selected) } label: {
                    HStack(spacing: 8) { Text(action.noun); Text("↩").font(.system(size: 11)).opacity(0.75) }
                }
                .buttonStyle(action == .delete ? AnyButtonStyle(DestructiveButtonStyle()) : AnyButtonStyle(PrimaryButtonStyle()))
                .keyboardShortcut(.return, modifiers: [])
            }
        }
        .padding(22)
        .frame(width: 400)
        .background(Theme.surface)
        .focusable()
        .focusEffectDisabled()
        .focused($focused)
        .onAppear { focused = true }
        .onKeyPress(.downArrow) { move(1); return .handled }
        .onKeyPress(.upArrow) { move(-1); return .handled }
        .onKeyPress("1") { choose(0); return .handled }
        .onKeyPress("2") { choose(1); return .handled }
        .onKeyPress("3") { choose(2); return .handled }
        .accessibilityElement(children: .contain)
    }

    private func row(_ scope: RecurrenceScope, index: Int) -> some View {
        let isSelected = index == selected
        return HStack(alignment: .top, spacing: 10) {
            Text("\(index + 1)")
                .font(.system(size: 11, weight: .medium)).foregroundStyle(Theme.text2)
                .frame(minWidth: 16, minHeight: 16)
                .padding(.top, 2)
            VStack(alignment: .leading, spacing: 1) {
                Text(scope.title).font(.system(size: 13, weight: .medium))
                Text(scope.detail).font(.system(size: 11)).foregroundStyle(Theme.text3)
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10).padding(.vertical, 8)
        .background(RoundedRectangle(cornerRadius: 8).fill(isSelected ? Theme.selection : Color.clear))
        .overlay(RoundedRectangle(cornerRadius: 8).stroke(isSelected ? Theme.accent.opacity(0.5) : Theme.line, lineWidth: 1))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) { Text(key).fontWeight(.semibold).foregroundStyle(Theme.text); Text(label) }
    }

    private func move(_ d: Int) {
        selected = min(max(selected + d, 0), options.count - 1)
    }

    private func choose(_ index: Int) {
        guard options.indices.contains(index) else { return }
        store.chooseRecurrenceScope(options[index], for: event, action: action)
    }
}

/// Type-erases a ButtonStyle so a single call site can pick between two concrete styles.
struct AnyButtonStyle: ButtonStyle {
    private let _makeBody: (Configuration) -> AnyView
    init<S: ButtonStyle>(_ style: S) { _makeBody = { AnyView(style.makeBody(configuration: $0)) } }
    func makeBody(configuration: Configuration) -> some View { _makeBody(configuration) }
}
