import Foundation
import SylvraCore
import Testing

@testable import FeaturePullRequest

/// Returns the demo details with a description that changes per load, or fails while `fails` is set.
private final class ChangingLoader: PullRequestDetailLoading, @unchecked Sendable {
    var body = "First version"
    var fails = false

    func loadDetail(for id: PullRequestID) async throws -> PullRequestDetail {
        if fails { throw URLError(.notConnectedToInternet) }
        var detail = DemoPullRequestDetailLoader.detail(for: id)
        detail.body = body
        return detail
    }
}

@MainActor
struct PullRequestRefreshTests {
    private let id = PullRequestID(owner: "acme", repository: "billing", number: 1234)

    @Test func refreshShowsChangesFromGitHub() async {
        let loader = ChangingLoader()
        let model = PullRequestScreenModel(loader: loader)
        await model.load(id)
        loader.body = "Second version"
        await model.refresh()
        #expect(model.detail?.body == "Second version")
        #expect(model.loadState == .loaded)
        #expect(!model.isRefreshing)
        #expect(model.lastUpdated != nil)
    }

    @Test func failingRefreshKeepsWhatIsShown() async {
        let loader = ChangingLoader()
        let model = PullRequestScreenModel(loader: loader)
        await model.load(id)
        loader.fails = true
        await model.refresh()
        #expect(model.detail?.body == "First version")
        #expect(model.loadState == .loaded)
    }
}
