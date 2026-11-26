import Testing

@testable import FeaturePullRequest

@MainActor
struct PullRequestTabBarTests {
    @Test func listsEveryTabInOrderWithCountsAndShortcuts() {
        let detail = DemoPullRequestDetailLoader.detail(for: .init(owner: "acme", repository: "billing", number: 1234))
        let items = PullRequestTabItem.items(for: detail)
        // An open pull request has no delivery yet.
        #expect(items.map(\.tab) == PullRequestScreenModel.Tab.allCases.filter { $0 != .delivery })
        #expect(items.map(\.shortcut.character) == ["1", "2", "3", "4", "5"])
        #expect(items.first?.count == nil)
        #expect(items.first { $0.tab == .commits }?.count == detail.commits.count)
        // The demo pull request has one failing check: the red badge counts that one, not all four.
        let checks = items.first { $0.tab == .checks }
        #expect(checks?.isAlert == true)
        #expect(checks?.count == 1)
    }

    /// The Delivery tab comes with the merge, and only where the app shows deliveries.
    @Test func mergedPullRequestsGetADeliveryTab() {
        let merged = DemoPullRequestDetailLoader.detail(for: .init(owner: "acme", repository: "billing", number: 812))
        #expect(PullRequestTabItem.items(for: merged, hasDelivery: true).last?.tab == .delivery)
        #expect(PullRequestTabItem.items(for: merged, hasDelivery: true).last?.shortcut.character == "6")
        #expect(!PullRequestTabItem.items(for: merged).contains { $0.tab == .delivery })
    }
}
