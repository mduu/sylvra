import Foundation
import SylvraCore
import Testing

@testable import FeatureDiff

/// After a rebase (a restacked layer), the changes since the last review leave out files only the rebase changed.
@MainActor
struct RebasedSinceReviewTests {
    private let id = PullRequestID(owner: "acme", repository: "billing", number: 1234)

    @Test func hidesFilesOnlyTheRebaseChanged() async {
        let model = DiffScreenModel(loader: RebasedLoader(isRewritten: true))
        await model.load(id, headSHA: "e08b5a1")
        await model.setScope(.sinceLastReview)
        #expect(model.files.map(\.path) == ["Sources/Billing/Invoice.swift", "Sources/Export/CSVEncoder.swift"])
        #expect(model.sinceReviewHiddenFiles == 1)
    }

    @Test func keepsEverythingWithoutARebase() async {
        // Without a force push, a file outside the pull request's diff is a real change (e.g. reverted).
        let model = DiffScreenModel(loader: RebasedLoader(isRewritten: false))
        await model.load(id, headSHA: "e08b5a1")
        await model.setScope(.sinceLastReview)
        #expect(model.files.count == 3)
        #expect(model.sinceReviewHiddenFiles == 0)
    }

    @Test func aForcePushCountsOnlyAfterTheReview() {
        let review = Date(timeIntervalSince1970: 1_000)
        #expect(ReviewProgress.isRewritten(forcePushedAt: review.addingTimeInterval(60), reviewedAt: review))
        #expect(!ReviewProgress.isRewritten(forcePushedAt: review.addingTimeInterval(-60), reviewedAt: review))
        #expect(!ReviewProgress.isRewritten(forcePushedAt: nil, reviewedAt: review))
        #expect(!ReviewProgress.isRewritten(forcePushedAt: review, reviewedAt: nil))
    }

    @Test func keepsRenamedFilesOfThePullRequest() {
        let pullRequest = [FileDiff(path: "New.swift", previousPath: "Old.swift", status: .renamed, hunks: [])]
        let since = [
            FileDiff(path: "Old.swift", status: .modified, hunks: []),
            FileDiff(path: "Elsewhere.swift", status: .modified, hunks: []),
        ]
        let restricted = SinceReviewFilter.restrict(since, to: pullRequest)
        #expect(restricted.files.map(\.path) == ["Old.swift"])
        #expect(restricted.hidden == 1)
    }
}

/// The demo pull request, rebased after the last review: the comparison also brings a file from below.
private struct RebasedLoader: DiffLoading {
    let isRewritten: Bool
    private let demo = DemoDiffLoader()

    func loadDiff(for id: PullRequestID) async throws -> PullRequestDiff { try await demo.loadDiff(for: id) }
    func loadFileContent(for id: PullRequestID, path: String, ref: String) async throws -> String { "" }
    func setViewed(_ viewed: Bool, path: String, pullRequestNodeID: String) async throws {}
    func loadReviewProgress(for id: PullRequestID) async throws -> ReviewProgress {
        var progress = try await demo.loadReviewProgress(for: id)
        progress.isRewrittenSinceReview = isRewritten
        return progress
    }
    func loadDiff(for id: PullRequestID, from base: String, to head: String) async throws -> [FileDiff] {
        try await demo.loadDiff(for: id, from: base, to: head)
            + [FileDiff(path: "Sources/Shared/FromBelow.swift", status: .modified, hunks: [])]
    }
}
