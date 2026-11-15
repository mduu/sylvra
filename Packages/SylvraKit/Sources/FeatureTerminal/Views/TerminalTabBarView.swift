import DesignSystem
import SwiftUI

/// A tab as shown in the tab strip.
struct TerminalTab: Identifiable, Equatable {
    let id: UUID
    let title: String
    let hasExited: Bool
}

/// Tab strip of the terminal panel with trailing actions (pure: data in, closures out).
struct TerminalTabBarView<Actions: View>: View {
    let tabs: [TerminalTab]
    let selection: UUID?
    let select: (UUID) -> Void
    let close: (UUID) -> Void
    let newTab: () -> Void
    let actions: Actions

    var body: some View {
        HStack(spacing: 6) {
            ScrollView(.horizontal, showsIndicators: false) {
                HStack(spacing: 4) {
                    ForEach(tabs) { tab in
                        TerminalTabRow(
                            tab: tab, isSelected: tab.id == selection, select: { select(tab.id) },
                            close: { close(tab.id) })
                    }
                }
            }
            Button(action: newTab) {
                Image(systemName: "plus")
            }
            .buttonStyle(.borderless)
            .help("New terminal tab")
            .accessibilityLabel("New terminal tab")
            Spacer(minLength: 8)
            actions
        }
        .padding(.horizontal, 8)
        .padding(.vertical, 5)
    }
}

private struct TerminalTabRow: View {
    let tab: TerminalTab
    let isSelected: Bool
    let select: () -> Void
    let close: () -> Void
    @State private var isHovering = false

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: tab.hasExited ? "stop.circle" : "terminal")
                .foregroundStyle(.secondary)
            Text(tab.title)
                .lineLimit(1)
                .truncationMode(.middle)
                .frame(maxWidth: 180, alignment: .leading)
            Button(action: close) {
                Image(systemName: "xmark")
                    .font(.caption2.weight(.semibold))
            }
            .buttonStyle(.borderless)
            .opacity(isSelected || isHovering ? 1 : 0)
            .help("Close tab")
            .accessibilityLabel("Close \(tab.title)")
        }
        .font(.callout)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .background(
            isSelected ? SylvraColor.brandPrimary.opacity(0.18) : .clear, in: RoundedRectangle(cornerRadius: 6)
        )
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
        .onHover { isHovering = $0 }
        .accessibilityAddTraits(isSelected ? [.isButton, .isSelected] : .isButton)
    }
}

#Preview {
    TerminalTabBarView(
        tabs: [
            .init(id: UUID(), title: "acme/billing #1234", hasExited: false),
            .init(id: UUID(), title: "Run tests", hasExited: true),
        ],
        selection: nil, select: { _ in }, close: { _ in }, newTab: {},
        actions: Image(systemName: "arrow.up.forward.app")
    )
    .frame(width: 600)
}
