import DesignSystem
import SwiftUI

/// Search field at the top of the inbox (pure). Our own field instead of `.searchable(placement: .sidebar)`:
/// the system draws that one on a material band that picks up the desktop picture (a blue-grey stripe above
/// the lavender sidebar in light mode).
struct InboxSearchField: View {
    @Binding var text: String
    let prompt: String
    @FocusState private var isFocused: Bool

    var body: some View {
        HStack(spacing: 6) {
            Image(systemName: "magnifyingglass").foregroundStyle(.secondary)
            TextField(prompt, text: $text)
                .textFieldStyle(.plain)
                .focused($isFocused)
                .onExitCommand { text = "" }
            if !text.isEmpty {
                Button {
                    text = ""
                } label: {
                    Image(systemName: "xmark.circle.fill").foregroundStyle(.tertiary)
                }
                .buttonStyle(.borderless)
                .help("Clear the search (esc)")
            }
        }
        .padding(.horizontal, 9)
        .padding(.vertical, 6)
        .background(SylvraColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
        .overlay(
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(isFocused ? SylvraColor.brandPrimary.opacity(0.6) : SylvraColor.codeHairline)
        )
        .padding(.horizontal, 10)
        .padding(.top, 8)
        .padding(.bottom, 6)
    }
}

#Preview("Inbox search field") {
    @Previewable @State var text = ""
    InboxSearchField(text: $text, prompt: "Search PRs")
        .frame(width: 300)
        .background(SylvraColor.surfaceSidebar)
}
