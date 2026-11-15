import Foundation
import SylvraCore

/// Reads review threads and performs review mutations.
///
/// Every write method maps to an explicit user action (product rule: never post to GitHub unasked).
public protocol ReviewService: Sendable {
    /// Threads of the pull request plus the viewer's pending review.
    func loadReview(for id: PullRequestID) async throws -> ReviewSnapshot

    /// Creates a pending review and returns its ID.
    func startPendingReview(pullRequestNodeID: String) async throws -> String

    /// Adds a new thread to the pending review.
    func addThread(reviewID: String, location: CodeLocation, body: String) async throws -> ReviewThread

    /// Posts a single comment immediately (a review with event `COMMENT` that contains one thread).
    func postComment(pullRequestNodeID: String, location: CodeLocation, body: String) async throws

    /// Replies to a thread, as part of the pending review if `reviewID` is given, otherwise immediately.
    func reply(threadID: String, reviewID: String?, body: String) async throws -> ReviewComment

    func setResolved(_ resolved: Bool, threadID: String) async throws

    func updateComment(id: String, body: String) async throws -> ReviewComment

    func deleteComment(id: String) async throws

    /// Adds or removes the viewer's reaction on a comment.
    func setReaction(_ reaction: Reaction, added: Bool, commentID: String) async throws

    /// Submits the pending review, or creates and submits a new review when `reviewID` is `nil`.
    func submitReview(pullRequestNodeID: String, reviewID: String?, event: ReviewEvent, body: String) async throws
}
