import Foundation
import SylvraCore

/// A review comment in a thread.
public struct ReviewComment: Identifiable, Hashable, Sendable {
    public let id: String
    public let author: UserRef
    public var body: String
    public let createdAt: Date
    public let url: URL?
    /// Part of the viewer's pending (not yet submitted) review.
    public let isPending: Bool
    public let viewerCanUpdate: Bool
    public let viewerCanDelete: Bool
    public var reactions: [ReactionGroup]

    public init(
        id: String, author: UserRef, body: String, createdAt: Date, url: URL? = nil, isPending: Bool = false,
        viewerCanUpdate: Bool = false, viewerCanDelete: Bool = false, reactions: [ReactionGroup] = []
    ) {
        self.reactions = reactions
        self.id = id
        self.author = author
        self.body = body
        self.createdAt = createdAt
        self.url = url
        self.isPending = isPending
        self.viewerCanUpdate = viewerCanUpdate
        self.viewerCanDelete = viewerCanDelete
    }
}

/// A review thread anchored to lines of the diff (see specs/architecture.md §4).
public struct ReviewThread: Identifiable, Hashable, Sendable {
    public let id: String
    public let location: CodeLocation
    public var isResolved: Bool
    /// The commented code changed since the comment was written.
    public let isOutdated: Bool
    public var comments: [ReviewComment]
    public let viewerCanReply: Bool
    public let viewerCanResolve: Bool

    public init(
        id: String, location: CodeLocation, isResolved: Bool = false, isOutdated: Bool = false,
        comments: [ReviewComment], viewerCanReply: Bool = true, viewerCanResolve: Bool = true
    ) {
        self.id = id
        self.location = location
        self.isResolved = isResolved
        self.isOutdated = isOutdated
        self.comments = comments
        self.viewerCanReply = viewerCanReply
        self.viewerCanResolve = viewerCanResolve
    }

    /// Resolved and outdated threads start collapsed.
    public var isCollapsedByDefault: Bool { isResolved || isOutdated }
}

/// Review state of a pull request: threads plus the viewer's pending review.
public struct ReviewSnapshot: Hashable, Sendable {
    /// GitHub node ID of the pull request (needed for mutations).
    public var pullRequestNodeID: String
    public var threads: [ReviewThread]
    /// ID of the viewer's pending review, if one exists.
    public var pendingReviewID: String?
    /// The viewer opened the pull request: GitHub refuses their approval or change request.
    public var viewerDidAuthor = false

    public init(
        pullRequestNodeID: String, threads: [ReviewThread], pendingReviewID: String? = nil,
        viewerDidAuthor: Bool = false
    ) {
        self.pullRequestNodeID = pullRequestNodeID
        self.threads = threads
        self.pendingReviewID = pendingReviewID
        self.viewerDidAuthor = viewerDidAuthor
    }
}

/// How a review is submitted (GitHub `PullRequestReviewEvent`).
public enum ReviewEvent: String, CaseIterable, Identifiable, Sendable {
    case comment = "COMMENT"
    case approve = "APPROVE"
    case requestChanges = "REQUEST_CHANGES"

    public var id: String { rawValue }
}
