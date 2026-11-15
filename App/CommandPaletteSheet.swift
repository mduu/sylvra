import DesignSystem
import SwiftUI

/// ⌘K: jump to a file or run a command by typing a few letters.
struct CommandPaletteSheet: View {
    struct Item: Identifiable {
        let id: String
        let title: String
        let subtitle: String
        let icon: String
        let action: () -> Void
    }

    let items: [Item]
    @Environment(\.dismiss) private var dismiss
    @State private var query = ""
    @State private var selection = 0
    @FocusState private var isFocused: Bool

    private var matches: [Item] {
        let needle = query.lowercased().filter { !$0.isWhitespace }
        guard !needle.isEmpty else { return items }
        return items.filter { Self.fuzzyMatches(needle, "\($0.title) \($0.subtitle)".lowercased()) }
    }

    /// All characters of `needle` appear in order in `text`.
    static func fuzzyMatches(_ needle: String, _ text: String) -> Bool {
        var remaining = needle[...]
        for character in text where character == remaining.first {
            remaining = remaining.dropFirst()
            if remaining.isEmpty { return true }
        }
        return remaining.isEmpty
    }

    var body: some View {
        VStack(spacing: 0) {
            HStack(spacing: 8) {
                Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
                TextField("Go to file or run a command…", text: $query)
                    .textFieldStyle(.plain)
                    .font(.title3)
                    .focused($isFocused)
                    .onSubmit(run)
                    .onKeyPress(.downArrow) {
                        selection = min(selection + 1, max(matches.count - 1, 0))
                        return .handled
                    }
                    .onKeyPress(.upArrow) {
                        selection = max(selection - 1, 0)
                        return .handled
                    }
            }
            .padding(14)
            Divider()
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 2) {
                        ForEach(Array(matches.enumerated()), id: \.element.id) { index, item in
                            row(item, isSelected: index == selection)
                                .id(index)
                                .onTapGesture {
                                    selection = index
                                    run()
                                }
                        }
                    }
                    .padding(6)
                }
                .onChange(of: selection) { _, index in proxy.scrollTo(index) }
            }
            .frame(height: 320)
        }
        .frame(width: 560)
        .background(SylvraColor.surfaceElevated)
        .onChange(of: query) { selection = 0 }
        .onAppear { isFocused = true }
        .onExitCommand { dismiss() }
    }

    private func row(_ item: Item, isSelected: Bool) -> some View {
        HStack(spacing: 10) {
            Image(systemName: item.icon).frame(width: 18).foregroundStyle(SylvraColor.brandPrimary)
            Text(item.title).lineLimit(1)
            Spacer(minLength: 8)
            Text(item.subtitle).font(.caption).foregroundStyle(.secondary).lineLimit(1).truncationMode(.head)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(isSelected ? SylvraColor.surfaceSelected : .clear, in: RoundedRectangle(cornerRadius: 7))
        .contentShape(Rectangle())
    }

    private func run() {
        guard matches.indices.contains(selection) else { return }
        let action = matches[selection].action
        dismiss()
        action()
    }
}

#Preview("Palette") {
    CommandPaletteSheet(items: [
        .init(id: "a", title: "InvoiceService.swift", subtitle: "Sources/Billing", icon: "doc", action: {}),
        .init(id: "b", title: "Run AI review", subtitle: "⌘⇧R", icon: "sparkles", action: {}),
    ])
}
