import SwiftUI

/// Centered search dialog for `P` (temporary overlay) and `⇧P` (permanent add). ↑/↓ move through
/// results, Return picks the highlighted one and closes, Esc closes. Picking someone already
/// overlaid for this session removes them again.
struct AddPersonDialog: View {
    @Environment(CalendarStore.self) private var store
    @State private var query = ""
    @State private var results: [DirectoryPerson] = []
    @State private var searching = false
    @State private var selection = 0
    @FocusState private var focused: Bool

    private var temporary: Bool { store.addPersonTemporary }
    private var looksLikeEmail: Bool { query.contains("@") && query.contains(".") }

    var body: some View {
        ZStack {
            Color.black.opacity(0.32).ignoresSafeArea().onTapGesture(perform: close)

            VStack(alignment: .leading, spacing: 12) {
                HStack(spacing: 10) {
                    Image(systemName: temporary ? "clock" : "person.badge.plus")
                        .font(.system(size: 14, weight: .medium))
                        .foregroundStyle(Theme.accent)
                        .frame(width: 28, height: 28)
                        .background(Circle().fill(Theme.accent.opacity(0.12)))
                    VStack(alignment: .leading, spacing: 1) {
                        Text(temporary ? "Temporary overlay" : "Permanent addition")
                            .font(.system(size: 14, weight: .semibold)).foregroundStyle(Theme.text)
                        Text(temporary ? "Shown on top of your calendar until you press Esc" : "Added to your sidebar for good")
                            .font(.system(size: 12)).foregroundStyle(Theme.text3)
                    }
                    Spacer()
                    if searching { ProgressView().controlSize(.small) }
                }

                TextField("Search name or email…", text: $query)
                    .textFieldStyle(.roundedBorder)
                    .font(.system(size: 14))
                    .focused($focused)
                    .onSubmit(commit)
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                    .onKeyPress(.escape) { close(); return .handled }

                if !results.isEmpty {
                    VStack(spacing: 2) {
                        ForEach(Array(results.enumerated()), id: \.element.id) { i, p in
                            row(p, selected: i == selection)
                                .onTapGesture { selection = i; commit() }
                        }
                    }
                } else if looksLikeEmail {
                    Text("Return adds \(query)").font(.system(size: 12)).foregroundStyle(Theme.text2)
                } else if !searching {
                    Text("Type two letters to search your organization, or a full email address.")
                        .font(.system(size: 12)).foregroundStyle(Theme.text3)
                }

                HStack(spacing: 10) {
                    HStack(spacing: 4) { KeyCap("↑"); KeyCap("↓"); Text("navigate") }
                    HStack(spacing: 4) { KeyCap("↵"); Text(temporary ? "overlay" : "add") }
                    HStack(spacing: 4) { KeyCap("esc"); Text("close") }
                    Spacer()
                }
                .font(.system(size: 11)).foregroundStyle(Theme.text3)
            }
            .padding(18)
            .frame(width: 440)
            .background(RoundedRectangle(cornerRadius: 12).fill(Theme.surface))
            .overlay(RoundedRectangle(cornerRadius: 12).stroke(Theme.line, lineWidth: 1))
            .shadow(color: .black.opacity(0.25), radius: 24, y: 8)
        }
        .transition(.opacity)
        .onAppear { DispatchQueue.main.asyncAfter(deadline: .now() + 0.05) { focused = true } }
        .task(id: query) {
            guard query.count >= 2 else { results = []; selection = 0; return }
            searching = true
            try? await Task.sleep(nanoseconds: 250_000_000)
            guard !Task.isCancelled else { return }
            results = await store.searchDirectory(query)
            selection = 0
            searching = false
        }
    }

    private func existing(_ p: DirectoryPerson) -> Source? {
        store.people.first { $0.calendarId == p.email.lowercased() }
    }

    private func row(_ p: DirectoryPerson, selected: Bool) -> some View {
        let src = existing(p)
        let status: String? = src == nil ? nil
            : store.temporaryPeople.contains(src!.id) ? (temporary ? "Overlaid · Return removes" : "Overlaid · Return keeps") : "In sidebar"
        return HStack(spacing: 10) {
            Image(systemName: "person.crop.circle").foregroundStyle(Theme.text3)
            VStack(alignment: .leading, spacing: 0) {
                Text(p.name).foregroundStyle(Theme.text)
                Text(p.email).font(.system(size: 11)).foregroundStyle(Theme.text3)
            }
            Spacer()
            if let status { Text(status).font(.system(size: 11)).foregroundStyle(Theme.text3) }
        }
        .padding(.horizontal, 8).padding(.vertical, 5)
        .background(RoundedRectangle(cornerRadius: 6).fill(selected ? Theme.accent.opacity(0.14) : .clear))
        .contentShape(Rectangle())
    }

    private func move(_ d: Int) {
        guard !results.isEmpty else { return }
        selection = min(max(selection + d, 0), results.count - 1)
    }

    private func close() { store.showAddPerson = false }

    private func commit() {
        if results.indices.contains(selection), !looksLikeEmail {
            let p = results[selection]
            if let src = existing(p) {
                if store.temporaryPeople.contains(src.id) {
                    if temporary { store.removePerson(src) } else { store.makePersonPermanent(src) }
                }
            } else {
                store.addPerson(p, temporary: temporary)
            }
        } else if looksLikeEmail {
            store.addPerson(name: "", email: query, temporary: temporary)
        } else { return }
        close()
    }
}
