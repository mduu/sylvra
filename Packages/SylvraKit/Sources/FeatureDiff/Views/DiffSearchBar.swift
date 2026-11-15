import DesignSystem
import SwiftUI

/// ⌘F bar above the diff: query, match count, previous / next (pure).
struct DiffSearchBar: View {
    @Binding var query: String
    let matchCount: Int
    let currentIndex: Int?
    var next: () -> Void = {}
    var previous: () -> Void = {}
    var close: () -> Void = {}
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 8) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField("Find in diff", text: $query)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onSubmit(next)
                .onExitCommand(perform: close)
            Text(countLabel).font(.caption.monospacedDigit()).foregroundStyle(.secondary).fixedSize()
            Button(action: previous) { Image(systemName: "chevron.up") }.help("Previous match")
            Button(action: next) { Image(systemName: "chevron.down") }
                .keyboardShortcut("g", modifiers: .command)
                .help("Next match (↩ or ⌘G)")
            Button(action: close) { Image(systemName: "xmark") }.help("Close (esc)")
        }
        .buttonStyle(.borderless)
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(SylvraColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 9))
        .overlay(RoundedRectangle(cornerRadius: 9).strokeBorder(SylvraColor.accentGold.opacity(0.5)))
        .padding(.horizontal, 10)
        .padding(.top, 6)
        .onAppear { isFocused = true }
    }

    private var countLabel: String {
        guard query.count >= 2 else { return "" }
        guard matchCount > 0 else { return String(localized: "No matches") }
        return currentIndex.map { String(localized: "\($0 + 1) of \(matchCount)") }
            ?? String(localized: "\(matchCount) matches")
    }
}

#Preview("Search bar") {
    DiffSearchBar(query: .constant("round"), matchCount: 4, currentIndex: 1).frame(width: 600)
}
