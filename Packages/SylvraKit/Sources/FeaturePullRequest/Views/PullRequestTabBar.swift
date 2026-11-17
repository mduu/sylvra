import DesignSystem
import SwiftUI
import SylvraCore

/// One tab of the PR column with its count (`nil`: no count) and whether the count signals a problem.
struct PullRequestTabItem: Identifiable {
    let tab: PullRequestScreenModel.Tab
    var count: Int?
    var isAlert = false

    var id: PullRequestScreenModel.Tab { tab }

    var title: String {
        switch tab {
        case .overview: String(localized: "Overview")
        case .files: String(localized: "Files")
        case .commits: String(localized: "Commits")
        case .checks: String(localized: "Checks")
        case .comments: String(localized: "Comments")
        }
    }

    var symbol: String {
        switch tab {
        case .overview: "info.circle"
        case .files: "doc.on.doc"
        case .commits: "arrow.triangle.branch"
        case .checks: "checkmark.seal"
        case .comments: "bubble.left.and.bubble.right"
        }
    }

    /// The tabs of a pull request with their counts. While checks fail, the checks badge turns red and
    /// counts the failing ones (a red total would read as "all failing").
    static func items(for detail: PullRequestDetail) -> [PullRequestTabItem] {
        let failing = detail.checks.count { $0.state == .failure || $0.state == .error }
        return [
            PullRequestTabItem(tab: .overview),
            PullRequestTabItem(tab: .files, count: detail.changedFiles),
            PullRequestTabItem(tab: .commits, count: detail.commits.count),
            PullRequestTabItem(
                tab: .checks, count: failing > 0 ? failing : detail.checks.count, isAlert: failing > 0),
            PullRequestTabItem(tab: .comments, count: detail.commentCount),
        ]
    }

    /// ⌘1 … ⌘5 in tab order.
    var shortcut: KeyEquivalent {
        KeyEquivalent(Character(String((PullRequestScreenModel.Tab.allCases.firstIndex(of: tab) ?? 0) + 1)))
    }
}

/// The PR column's tabs side by side, always all visible (pure). Narrow columns get smaller text, then
/// symbols with counts and the name only on the selected tab, then symbols only (names in the tooltips) —
/// never a menu. ⌘1–⌘5 switch tabs.
struct PullRequestTabBar: View {
    let items: [PullRequestTabItem]
    @Binding var selection: PullRequestScreenModel.Tab

    enum Style: CaseIterable { case full, compact, selectedTitle, symbols }

    var body: some View {
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

    private func tabButton(_ item: PullRequestTabItem, style: Style) -> some View {
        let isSelected = selection == item.tab
        return Button {
            selection = item.tab
        } label: {
            HStack(spacing: 4) {
                if style != .compact { Image(systemName: item.symbol) }
                if Self.showsTitle(style, isSelected: isSelected) { Text(item.title) }
                if let count = item.count {
                    CountBadge(count: count, isAlert: item.isAlert, isSelected: isSelected)
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
        .keyboardShortcut(item.shortcut, modifiers: .command)
        .help("\(item.title) (⌘\(String(item.shortcut.character)))")
        .accessibilityLabel(item.title)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    static func showsTitle(_ style: Style, isSelected: Bool) -> Bool {
        switch style {
        case .full, .compact: true
        case .selectedTitle: isSelected
        case .symbols: false
        }
    }
}

/// A count as a small capsule (pure): grey, violet on the selected tab, red when it signals a problem.
struct CountBadge: View {
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
    @Previewable @State var selection = PullRequestScreenModel.Tab.overview
    let items = [
        PullRequestTabItem(tab: .overview), PullRequestTabItem(tab: .files, count: 7),
        PullRequestTabItem(tab: .commits, count: 4), PullRequestTabItem(tab: .checks, count: 4, isAlert: true),
        PullRequestTabItem(tab: .comments, count: 5),
    ]
    VStack(alignment: .leading, spacing: 16) {
        PullRequestTabBar(items: items, selection: $selection).frame(width: 520, alignment: .leading)
        PullRequestTabBar(items: items, selection: $selection).frame(width: 360, alignment: .leading)
        PullRequestTabBar(items: items, selection: $selection).frame(width: 260, alignment: .leading)
    }
    .padding()
}
