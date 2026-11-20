import DesignSystem
import SwiftUI
import SylvraCore

/// One tab of the PR column (shown with `SectionTabBar`) with its count (`nil`: no count) and whether the count signals a problem.
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

    /// For the shared tab bar (same look as the AI inspector's tabs).
    var barItem: SectionTabItem<PullRequestScreenModel.Tab> {
        SectionTabItem(
            tab: tab, title: title, symbol: symbol, count: count, isAlert: isAlert, shortcut: shortcut)
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
        SectionTabBar(items: items.map(\.barItem), selection: $selection).frame(width: 520, alignment: .leading)
        SectionTabBar(items: items.map(\.barItem), selection: $selection).frame(width: 260, alignment: .leading)
    }
    .padding()
}
