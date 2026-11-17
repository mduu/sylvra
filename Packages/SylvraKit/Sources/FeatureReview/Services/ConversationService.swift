import Foundation
import SylvraCore

/// Reads and writes the conversation of a pull request (comments on the pull request itself).
///
/// Every write method maps to an explicit user action (product rule: never post to GitHub unasked).
public protocol ConversationService: Sendable {
    func loadConversation(for id: PullRequestID) async throws -> Conversation

    /// Posts a new comment on the pull request right away.
    func addComment(pullRequestNodeID: String, body: String) async throws -> ConversationEntry

    /// Changes the text of a comment or of a submitted review; returns the stored text.
    func updateBody(of entry: ConversationEntry, to body: String) async throws -> String

    func deleteComment(id: String) async throws

    /// Adds or removes the viewer's reaction on a comment or review.
    func setReaction(_ reaction: Reaction, added: Bool, subjectID: String) async throws
}
