import Foundation
import Platform
import SylvraCore
import Testing

@testable import FeatureReview

@MainActor
struct SubmitReviewTests {
    private let id = PullRequestID(owner: "acme", repository: "submit-\(UUID().uuidString)", number: 1)

    @Test func submitFollowsGitHubsRules() {
        func problem(_ event: ReviewEvent, body: String = "", pending: Int = 0, own: Bool = false) -> Bool {
            ReviewScreenModel.submitProblem(event: event, body: body, pendingCount: pending, viewerDidAuthor: own)
                != nil
        }
        #expect(!problem(.approve))
        #expect(problem(.approve, body: "LGTM", own: true))
        #expect(problem(.requestChanges, pending: 3))
        #expect(problem(.requestChanges, body: "Fix it", own: true))
        #expect(!problem(.requestChanges, body: "Fix it"))
        #expect(problem(.comment, body: "  "))
        #expect(!problem(.comment, pending: 1))
        #expect(!problem(.comment, body: "Looks fine", own: true))
    }

    // Regression: GitHub's error was shown by the window behind the sheet, which opened a second window.
    @Test func aRefusedSubmitIsShownInTheSheet() async {
        let model = ReviewScreenModel(service: RefusingSubmitService())
        await model.load(id)
        model.isSubmitSheetPresented = true
        model.submitBody = "Looks fine"
        await model.submitReview()
        #expect(model.submitError != nil)
        #expect(model.errorMessage == nil)
        #expect(model.isSubmitSheetPresented)
    }
}

/// Demo data, but GitHub refuses the review.
private struct RefusingSubmitService: ReviewService {
    private let demo = DemoReviewService()

    func loadReview(for id: PullRequestID) async throws -> ReviewSnapshot { try await demo.loadReview(for: id) }
    func startPendingReview(pullRequestNodeID: String) async throws -> String { "r" }
    func addThread(reviewID: String, location: CodeLocation, body: String) async throws -> ReviewThread {
        try await demo.addThread(reviewID: reviewID, location: location, body: body)
    }
    func postComment(pullRequestNodeID: String, location: CodeLocation, body: String) async throws {}
    func reply(threadID: String, reviewID: String?, body: String) async throws -> ReviewComment {
        try await demo.reply(threadID: threadID, reviewID: reviewID, body: body)
    }
    func setResolved(_ resolved: Bool, threadID: String) async throws {}
    func updateComment(id: String, body: String) async throws -> ReviewComment {
        try await demo.updateComment(id: id, body: body)
    }
    func deleteComment(id: String) async throws {}
    func setReaction(_ reaction: Reaction, added: Bool, commentID: String) async throws {}
    func submitReview(pullRequestNodeID: String, reviewID: String?, event: ReviewEvent, body: String) async throws {
        throw GitHubError.notAuthenticated
    }
}
