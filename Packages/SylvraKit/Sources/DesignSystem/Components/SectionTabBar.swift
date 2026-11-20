import SwiftUI

/// One tab of a `SectionTabBar`: name, symbol, count (`nil`: none) and whether the count signals a problem.
public struct SectionTabItem<Tab: Hashable>: Identifiable {
    public let tab: Tab
    public let title: String
    public let symbol: String
    public var count: Int?
    public var isAlert: Bool
    /// ⌘ + this key selects the tab (`nil`: no shortcut).
    public var shortcut: KeyEquivalent?

    public var id: Tab { tab }

    public init(
        tab: Tab, title: String, symbol: String, count: Int? = nil, isAlert: Bool = false,
        shortcut: KeyEquivalent? = nil
    ) {
        self.tab = tab
        self.title = title
        self.symbol = symbol
        self.count = count
        self.isAlert = isAlert
        self.shortcut = shortcut
    }
}

/// Tabs side by side, always all visible (pure), as in the pull request column and the AI inspector. Narrow
/// columns get smaller text, then symbols with counts and the name only on the selected tab, then symbols
/// only (names in the tooltips) — never a menu.
public struct SectionTabBar<Tab: Hashable>: View {
    let items: [SectionTabItem<Tab>]
    @Binding var selection: Tab

    public enum Style: CaseIterable { case full, compact, selectedTitle, symbols }

    public init(items: [SectionTabItem<Tab>], selection: Binding<Tab>) {
        self.items = items
        self._selection = selection
    }

    public var body: some View {
        ViewThatFits(in: .horizontal) {
            ForEach(Style.allCases, id: \.self) { style in
                bar(style).fixedSize()
            }
        }
    }

    private func bar(_ style: Style) -> some View {
        HStack(spacing: 2) {
            ForEach(items) { item in
                tabButton(item, style: style)
            }
        }
        .padding(2)
        .background(.quaternary.opacity(0.5), in: RoundedRectangle(cornerRadius: 8))
    }

    private func tabButton(_ item: SectionTabItem<Tab>, style: Style) -> some View {
        let isSelected = selection == item.tab
        return Button {
            selection = item.tab
        } label: {
            HStack(spacing: 4) {
                if item.isAlert {
                    // A problem shows a warning in every style (also where other tabs have no symbol).
                    Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
                } else if style != .compact {
                    Image(systemName: item.symbol)
                }
                if Self.showsTitle(style, isSelected: isSelected) { Text(item.title) }
                if let count = item.count {
                    TabCountBadge(count: count, isAlert: item.isAlert, isSelected: isSelected)
                }
            }
            .font(style == .full ? .callout : .caption)
            .fontWeight(isSelected ? .semibold : .regular)
            .lineLimit(1)
            .padding(.horizontal, style == .full ? 9 : 7)
            .padding(.vertical, 4)
            .background(
                isSelected ? AnyShapeStyle(SylvraColor.brandPrimary.opacity(0.18)) : AnyShapeStyle(.clear),
                in: RoundedRectangle(cornerRadius: 6)
            )
            .contentShape(RoundedRectangle(cornerRadius: 6))
        }
        .buttonStyle(.plain)
        .modifier(CommandShortcut(key: item.shortcut))
        .help(Self.help(item))
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    static func help(_ item: SectionTabItem<Tab>) -> String {
        let title = item.isAlert ? "\(item.title) — failing" : item.title
        return item.shortcut.map { "\(title) (⌘\(String($0.character)))" } ?? title
    }

    static func showsTitle(_ style: Style, isSelected: Bool) -> Bool {
        switch style {
        case .full, .compact: true
        case .selectedTitle: isSelected
        case .symbols: false
        }
    }
}

/// ⌘ + key, or nothing.
private struct CommandShortcut: ViewModifier {
    let key: KeyEquivalent?

    func body(content: Content) -> some View {
        if let key {
            content.keyboardShortcut(key, modifiers: .command)
        } else {
            content
        }
    }
}

/// A tab's count as a small capsule (pure): grey, violet on the selected tab, red when it signals a problem.
struct TabCountBadge: View {
    let count: Int
    var isAlert = false
    var isSelected = false

    var body: some View {
        Text(verbatim: "\(count)")
            .font(.caption2.weight(.semibold))
            .monospacedDigit()
            .foregroundStyle(isAlert || isSelected ? AnyShapeStyle(.white) : AnyShapeStyle(.secondary))
            .padding(.horizontal, 5)
            .frame(minWidth: 16)
            .background(background, in: Capsule())
    }

    private var background: AnyShapeStyle {
        if isAlert { return AnyShapeStyle(Color.red) }
        if isSelected { return AnyShapeStyle(SylvraColor.brandPrimary) }
        return AnyShapeStyle(.quaternary)
    }
}

#Preview {
    @Previewable @State var selection = "findings"
    let items = [
        SectionTabItem(tab: "findings", title: "Findings", symbol: "exclamationmark.bubble", count: 4),
        SectionTabItem(tab: "patterns", title: "Patterns", symbol: "square.grid.3x3", count: 3),
        SectionTabItem(tab: "chat", title: "Chat", symbol: "bubble.left.and.text.bubble.right"),
    ]
    VStack(alignment: .leading, spacing: 16) {
        SectionTabBar(items: items, selection: $selection).frame(width: 360, alignment: .leading)
        SectionTabBar(items: items, selection: $selection).frame(width: 220, alignment: .leading)
        SectionTabBar(items: items, selection: $selection).frame(width: 150, alignment: .leading)
    }
    .padding()
}
