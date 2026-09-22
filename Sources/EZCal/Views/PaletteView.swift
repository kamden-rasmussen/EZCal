import SwiftUI

/// ⌘K: search events, jump to dates, run any command.
struct PaletteView: View {
    @Environment(CalendarStore.self) private var store
    @State private var query = ""
    @State private var selected = 0
    @FocusState private var focused: Bool

    private var items: [PaletteItem] { store.paletteItems(for: query) }

    private var sections: [(title: String, rows: [PaletteItem])] {
        var order: [String] = []
        var map: [String: [PaletteItem]] = [:]
        for it in items {
            if map[it.group] == nil { order.append(it.group) }
            map[it.group, default: []].append(it)
        }
        return order.map { ($0, map[$0]!) }
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 10) {
                Image(systemName: "magnifyingglass").font(.system(size: 15)).foregroundStyle(Theme.text3)
                TextField("Search events or type a command", text: $query)
                    .textFieldStyle(.plain)
                    .font(.system(size: 16))
                    .focused($focused)
                    .onSubmit { run(selected) }
                    .onKeyPress(.downArrow) { move(1); return .handled }
                    .onKeyPress(.upArrow) { move(-1); return .handled }
                KeyCap("esc")
            }
            .padding(.horizontal, 18).frame(height: 56)
            Divider().overlay(Theme.line)

            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(alignment: .leading, spacing: 6) {
                        let flat = items
                        if flat.isEmpty {
                            Text("No matches").foregroundStyle(Theme.text3).padding(20)
                        }
                        ForEach(sections, id: \.title) { section in
                            VStack(alignment: .leading, spacing: 1) {
                                SectionLabel(section.title).padding(.horizontal, 10).padding(.top, 8).padding(.bottom, 4)
                                ForEach(section.rows) { it in
                                    let idx = flat.firstIndex { $0.id == it.id } ?? 0
                                    row(it, selected: idx == selected)
                                        .id(it.id)
                                        .onTapGesture { run(idx) }
                                }
                            }
                        }
                    }
                    .padding(8)
                }
                .onChange(of: selected) { _, new in
                    let flat = items
                    if flat.indices.contains(new) { proxy.scrollTo(flat[new].id) }
                }
            }

            HStack(spacing: 16) {
                hint("↑↓", "navigate"); hint("↩", "run"); hint("esc", "close")
                Spacer()
                Text("Try “go to friday”, “show priya”, “add zoom”").foregroundStyle(Theme.text3)
            }
            .font(.system(size: 12)).foregroundStyle(Theme.text2)
            .padding(.horizontal, 18).frame(height: 40)
            .background(Theme.hover.opacity(0.6))
        }
        .frame(width: 680, height: 540)
        .background(Theme.surface)
        .onAppear { query = store.paletteQuery; focused = true }
        .onChange(of: query) { _, _ in selected = 0 }
    }

    private func row(_ it: PaletteItem, selected: Bool) -> some View {
        HStack(spacing: 12) {
            Text(it.icon)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(it.tint ?? Theme.text2)
                .frame(width: 22, height: 22)
                .background(RoundedRectangle(cornerRadius: 6).fill(it.tint.map { $0.opacity(0.18) } ?? Theme.hover))
            Text(it.title).foregroundStyle(Theme.text).lineLimit(1)
            Spacer()
            if !it.subtitle.isEmpty { Text(it.subtitle).font(.system(size: 12)).foregroundStyle(Theme.text3) }
            if !it.key.isEmpty { KeyCap(it.key) }
        }
        .padding(.horizontal, 10).frame(height: 38)
        .background(RoundedRectangle(cornerRadius: 8).fill(selected ? Theme.selection : .clear))
        .contentShape(Rectangle())
        .accessibilityElement(children: .combine)
        .accessibilityAddTraits(.isButton)
    }

    private func hint(_ key: String, _ label: String) -> some View {
        HStack(spacing: 5) { Text(key).fontWeight(.semibold).foregroundStyle(Theme.text); Text(label) }
    }

    private func move(_ d: Int) {
        let n = items.count
        guard n > 0 else { return }
        selected = min(max(selected + d, 0), n - 1)
    }

    private func run(_ index: Int) {
        let flat = items
        guard flat.indices.contains(index) else { return }
        let item = flat[index]
        store.sheet = nil
        Task { @MainActor in
            try? await Task.sleep(nanoseconds: 200_000_000)   // let the sheet finish closing
            item.run()
        }
    }
}
