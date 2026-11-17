import Testing

@testable import FeaturePullRequest

@MainActor
struct PullRequestTabBarTests {
    @Test func listsEveryTabInOrderWithCountsAndShortcuts() {
        let detail = DemoPullRequestDetailLoader.detail(for: .init(owner: "acme", repository: "billing", number: 1234))
        let items = PullRequestTabItem.items(for: detail)
        #expect(items.map(\.tab) == PullRequestScreenModel.Tab.allCases)
        #expect(items.map(\.shortcut.character) == ["1", "2", "3", "4", "5"])
        #expect(items.first?.count == nil)
        #expect(items.first { $0.tab == .commits }?.count == detail.commits.count)
        // The demo pull request has a failing check.
        #expect(items.first { $0.tab == .checks }?.isAlert == true)
    }

    @Test func narrowBarsKeepTheSelectedTabsName() {
        #expect(PullRequestTabBar.showsTitle(.selectedTitle, isSelected: true))
        #expect(!PullRequestTabBar.showsTitle(.selectedTitle, isSelected: false))
        #expect(!PullRequestTabBar.showsTitle(.symbols, isSelected: true))
        #expect(PullRequestTabBar.showsTitle(.compact, isSelected: false))
    }
}
