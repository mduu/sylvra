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
        // The demo pull request has one failing check: the red badge counts that one, not all four.
        let checks = items.first { $0.tab == .checks }
        #expect(checks?.isAlert == true)
        #expect(checks?.count == 1)
    }
}
