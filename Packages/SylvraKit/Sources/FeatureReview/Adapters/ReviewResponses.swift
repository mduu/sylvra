import Foundation
import SylvraCore

// MARK: - Response DTOs (GraphQL JSON → domain)

struct ReviewResponse: Decodable, Sendable {
    let repository: Repository?
    struct Repository: Decodable, Sendable { let pullRequest: PullRequestNode? }

    struct PullRequestNode: Decodable, Sendable {
        let id: String
        let viewerDidAuthor: Bool?
        let reviews: Nodes<PendingReviewNode>
        let reviewThreads: Nodes<ThreadNode>

        var snapshot: ReviewSnapshot {
            ReviewSnapshot(
                pullRequestNodeID: id,
                threads: reviewThreads.values.compactMap(\.thread),
                pendingReviewID: reviews.values.first { $0.viewerDidAuthor }?.id,
                viewerDidAuthor: viewerDidAuthor ?? false)
        }
    }

    struct PendingReviewNode: Decodable, Sendable {
        let id: String
        let viewerDidAuthor: Bool
    }
}

struct Nodes<Element: Decodable & Sendable>: Decodable, Sendable {
    let nodes: [Element?]
    var values: [Element] { nodes.compactMap { $0 } }
}

struct ThreadNode: Decodable, Sendable {
    let id: String
    let isResolved: Bool
    let isOutdated: Bool
    let path: String
    let line: Int?
    let startLine: Int?
    let originalLine: Int?
    let originalStartLine: Int?
    let diffSide: String
    let viewerCanReply: Bool
    let viewerCanResolve: Bool
    let viewerCanUnresolve: Bool
    let comments: Nodes<CommentNode>

    /// Outdated threads have no current `line`; they fall back to the original line.
    /// File-level threads (no line at all) are not shown inline and are skipped.
    var thread: ReviewThread? {
        guard let anchor = line ?? originalLine else { return nil }
        let location = CodeLocation(
            path: path,
            line: anchor,
            side: CodeLocation.Side(rawValue: diffSide) ?? .right,
            startLine: line == nil ? originalStartLine : startLine)
        return ReviewThread(
            id: id,
            location: location,
            isResolved: isResolved,
            isOutdated: isOutdated,
            comments: comments.values.map(\.comment),
            viewerCanReply: viewerCanReply,
            viewerCanResolve: isResolved ? viewerCanUnresolve : viewerCanResolve)
    }
}

struct CommentNode: Decodable, Sendable {
    let id: String
    let body: String
    let createdAt: Date
    let url: URL?
    /// Review comments and reviews have a state; conversation comments don't.
    let state: String?
    let viewerCanUpdate: Bool
    let viewerCanDelete: Bool
    let author: Author?
    let reactionGroups: [ReactionGroupNode]?

    struct ReactionGroupNode: Decodable, Sendable {
        let content: String
        let viewerHasReacted: Bool
        let reactors: Count
        struct Count: Decodable, Sendable { let totalCount: Int }
    }

    struct Author: Decodable, Sendable {
        let login: String
        let avatarUrl: URL?
        let name: String?
    }

    var comment: ReviewComment {
        ReviewComment(
            id: id,
            author: UserRef(
                login: author?.login ?? "ghost",
                name: author?.name.flatMap { $0.isEmpty ? nil : $0 },
                avatarURL: author?.avatarUrl),
            body: body.replacingOccurrences(of: "\r\n", with: "\n"),
            createdAt: createdAt,
            url: url,
            isPending: state == "PENDING",
            viewerCanUpdate: viewerCanUpdate,
            viewerCanDelete: viewerCanDelete,
            reactions: (reactionGroups ?? []).compactMap { group in
                guard let reaction = Reaction(rawValue: group.content), group.reactors.totalCount > 0 else {
                    return nil
                }
                return ReactionGroup(
                    reaction: reaction, count: group.reactors.totalCount, viewerHasReacted: group.viewerHasReacted)
            })
    }
}

struct StartReviewResponse: Decodable, Sendable {
    let addPullRequestReview: Payload?
    struct Payload: Decodable, Sendable { let pullRequestReview: Review? }
    struct Review: Decodable, Sendable { let id: String }
}

struct AddThreadResponse: Decodable, Sendable {
    let addPullRequestReviewThread: Payload?
    struct Payload: Decodable, Sendable { let thread: ThreadNode? }
}

struct ReplyResponse: Decodable, Sendable {
    let addPullRequestReviewThreadReply: Payload?
    struct Payload: Decodable, Sendable { let comment: CommentNode? }
}

struct UpdateCommentResponse: Decodable, Sendable {
    let updatePullRequestReviewComment: Payload?
    struct Payload: Decodable, Sendable { let pullRequestReviewComment: CommentNode? }
}

/// For mutations whose payload is not needed.
struct EmptyResponse: Decodable, Sendable {}
