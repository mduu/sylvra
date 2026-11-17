import Foundation
import SylvraCore

/// One entry of a pull request's conversation (the comments on the pull request itself, not on code):
/// a comment or a submitted review.
public struct ConversationEntry: Identifiable, Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case comment
        case review(ReviewState)
    }

    /// The outcome of a submitted review.
    public enum ReviewState: String, Hashable, Sendable {
        case approved = "APPROVED"
        case changesRequested = "CHANGES_REQUESTED"
        case commented = "COMMENTED"
        case dismissed = "DISMISSED"
    }

    public let kind: Kind
    public var comment: ReviewComment

    public init(kind: Kind, comment: ReviewComment) {
        self.kind = kind
        self.comment = comment
    }

    public var id: String { comment.id }

    /// A review without text ("approved these changes") is shown as a slim event line.
    public var isEvent: Bool {
        if case .review = kind { return comment.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
        return false
    }

    /// Only comments can be deleted; a submitted review stays (GitHub allows editing its text).
    public var canDelete: Bool { kind == .comment && comment.viewerCanDelete }
}

/// The conversation of a pull request, oldest first (like GitHub).
public struct Conversation: Hashable, Sendable {
    /// GitHub node ID of the pull request (subject of new comments).
    public var pullRequestNodeID: String
    public var entries: [ConversationEntry]

    public init(pullRequestNodeID: String, entries: [ConversationEntry]) {
        self.pullRequestNodeID = pullRequestNodeID
        self.entries = entries.sorted { $0.comment.createdAt < $1.comment.createdAt }
    }

    /// Entries with text (comments and reviews with a summary), events excluded.
    public var commentCount: Int { entries.count { !$0.isEvent } }
}

/// GitHub's *Quote reply*: conversation comments have no threads, an answer quotes what it refers to.
public enum QuoteReply {
    /// `text` quoted line by line, followed by an empty line for the answer; appended to an existing draft.
    public static func draft(quoting text: String, into draft: String = "") -> String {
        let quoted = text.trimmingCharacters(in: .whitespacesAndNewlines)
            .components(separatedBy: "\n")
            .map { $0.isEmpty ? ">" : "> \($0)" }
            .joined(separator: "\n")
        let existing = draft.trimmingCharacters(in: .whitespacesAndNewlines)
        return (existing.isEmpty ? "" : existing + "\n\n") + quoted + "\n\n"
    }
}
