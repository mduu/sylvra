import Foundation
import Platform
import SylvraCore

/// Review threads and mutations via GitHub GraphQL.
public struct GitHubReviewService: ReviewService {
    private let client: GitHubClient

    public init(client: GitHubClient) {
        self.client = client
    }

    public func loadReview(for id: PullRequestID) async throws -> ReviewSnapshot {
        let response = try await client.graphQL(
            ReviewQueries.load,
            variables: ["owner": .string(id.owner), "name": .string(id.repository), "number": .int(id.number)],
            as: ReviewResponse.self
        )
        guard let pullRequest = response.repository?.pullRequest else {
            throw GitHubError.graphQL(["Pull request \(id) not found"])
        }
        return pullRequest.snapshot
    }

    public func startPendingReview(pullRequestNodeID: String) async throws -> String {
        let response = try await client.graphQL(
            ReviewQueries.startReview, variables: ["id": .string(pullRequestNodeID)], as: StartReviewResponse.self)
        guard let id = response.addPullRequestReview?.pullRequestReview?.id else {
            throw GitHubError.decoding("addPullRequestReview returned no review")
        }
        return id
    }

    public func addThread(reviewID: String, location: CodeLocation, body: String) async throws -> ReviewThread {
        var variables = Self.locationVariables(location)
        variables["reviewID"] = .string(reviewID)
        variables["body"] = .string(body)
        let response = try await client.graphQL(
            ReviewQueries.addThread, variables: variables, as: AddThreadResponse.self)
        guard let thread = response.addPullRequestReviewThread?.thread?.thread else {
            throw GitHubError.decoding("addPullRequestReviewThread returned no thread")
        }
        return thread
    }

    public func postComment(pullRequestNodeID: String, location: CodeLocation, body: String) async throws {
        var variables = Self.locationVariables(location)
        variables["id"] = .string(pullRequestNodeID)
        variables["body"] = .string(body)
        _ = try await client.graphQL(ReviewQueries.postComment, variables: variables, as: EmptyResponse.self)
    }

    public func reply(threadID: String, reviewID: String?, body: String) async throws -> ReviewComment {
        let response = try await client.graphQL(
            ReviewQueries.reply,
            variables: [
                "threadID": .string(threadID), "reviewID": reviewID.map(GraphQLValue.string) ?? .null,
                "body": .string(body),
            ],
            as: ReplyResponse.self
        )
        guard let comment = response.addPullRequestReviewThreadReply?.comment?.comment else {
            throw GitHubError.decoding("addPullRequestReviewThreadReply returned no comment")
        }
        return comment
    }

    public func setResolved(_ resolved: Bool, threadID: String) async throws {
        _ = try await client.graphQL(
            resolved ? ReviewQueries.resolve : ReviewQueries.unresolve, variables: ["threadID": .string(threadID)],
            as: EmptyResponse.self)
    }

    public func updateComment(id: String, body: String) async throws -> ReviewComment {
        let response = try await client.graphQL(
            ReviewQueries.updateComment, variables: ["id": .string(id), "body": .string(body)],
            as: UpdateCommentResponse.self)
        guard let comment = response.updatePullRequestReviewComment?.pullRequestReviewComment?.comment else {
            throw GitHubError.decoding("updatePullRequestReviewComment returned no comment")
        }
        return comment
    }

    public func deleteComment(id: String) async throws {
        _ = try await client.graphQL(
            ReviewQueries.deleteComment, variables: ["id": .string(id)], as: EmptyResponse.self)
    }

    public func setReaction(_ reaction: Reaction, added: Bool, commentID: String) async throws {
        _ = try await client.graphQL(
            added ? ReviewQueries.addReaction : ReviewQueries.removeReaction,
            variables: ["id": .string(commentID), "content": .string(reaction.rawValue)], as: EmptyResponse.self)
    }

    public func submitReview(pullRequestNodeID: String, reviewID: String?, event: ReviewEvent, body: String)
        async throws
    {
        let body: GraphQLValue = body.isEmpty ? .null : .string(body)
        if let reviewID {
            _ = try await client.graphQL(
                ReviewQueries.submit,
                variables: ["reviewID": .string(reviewID), "event": .string(event.rawValue), "body": body],
                as: EmptyResponse.self)
        } else {
            _ = try await client.graphQL(
                ReviewQueries.createAndSubmit,
                variables: ["id": .string(pullRequestNodeID), "event": .string(event.rawValue), "body": body],
                as: EmptyResponse.self)
        }
    }

    static func locationVariables(_ location: CodeLocation) -> [String: GraphQLValue] {
        [
            "path": .string(location.path),
            "line": .int(location.line),
            "side": .string(location.side.rawValue),
            "startLine": location.startLine.map(GraphQLValue.int) ?? .null,
            "startSide": location.startLine == nil ? .null : .string(location.side.rawValue),
        ]
    }
}

// MARK: - Queries

enum ReviewQueries {
    /// GraphQL rejects unused fragments, so documents include only what they use.
    static let commentFragment = """
        fragment CommentFields on PullRequestReviewComment {
          id body createdAt url state viewerCanUpdate viewerCanDelete
          author { login avatarUrl ... on User { name } }
          reactionGroups { content viewerHasReacted reactors { totalCount } }
        }

        """

    static let threadFragments =
        commentFragment + """
            fragment ThreadFields on PullRequestReviewThread {
              id isResolved isOutdated path line startLine originalLine originalStartLine diffSide
              viewerCanReply viewerCanResolve viewerCanUnresolve
              comments(first: 50) { nodes { ...CommentFields } }
            }
            """

    static let load = """
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              id
              reviews(first: 5, states: PENDING) { nodes { id viewerDidAuthor } }
              reviewThreads(first: 100) { nodes { ...ThreadFields } }
            }
          }
        }
        """ + threadFragments

    static let addReaction = """
        mutation($id: ID!, $content: ReactionContent!) {
          addReaction(input: { subjectId: $id, content: $content }) { clientMutationId }
        }
        """

    static let removeReaction = """
        mutation($id: ID!, $content: ReactionContent!) {
          removeReaction(input: { subjectId: $id, content: $content }) { clientMutationId }
        }
        """

    static let startReview = """
        mutation($id: ID!) {
          addPullRequestReview(input: { pullRequestId: $id }) { pullRequestReview { id } }
        }
        """

    static let locationParameters =
        "$path: String!, $line: Int!, $side: DiffSide!, $startLine: Int, $startSide: DiffSide, $body: String!"
    static let locationArguments =
        "path: $path, line: $line, side: $side, startLine: $startLine, startSide: $startSide, body: $body"

    static let addThread = """
        mutation($reviewID: ID!, \(locationParameters)) {
          addPullRequestReviewThread(input: { pullRequestReviewId: $reviewID, \(locationArguments) }) {
            thread { ...ThreadFields }
          }
        }
        """ + threadFragments

    static let postComment = """
        mutation($id: ID!, \(locationParameters)) {
          addPullRequestReview(input: { pullRequestId: $id, event: COMMENT, threads: [{ \(locationArguments) }] }) {
            pullRequestReview { id }
          }
        }
        """

    static let reply = """
        mutation($threadID: ID!, $reviewID: ID, $body: String!) {
          addPullRequestReviewThreadReply(
            input: { pullRequestReviewThreadId: $threadID, pullRequestReviewId: $reviewID, body: $body }
          ) { comment { ...CommentFields } }
        }
        """ + commentFragment

    static let resolve = """
        mutation($threadID: ID!) { resolveReviewThread(input: { threadId: $threadID }) { thread { id } } }
        """

    static let unresolve = """
        mutation($threadID: ID!) { unresolveReviewThread(input: { threadId: $threadID }) { thread { id } } }
        """

    static let updateComment = """
        mutation($id: ID!, $body: String!) {
          updatePullRequestReviewComment(input: { pullRequestReviewCommentId: $id, body: $body }) {
            pullRequestReviewComment { ...CommentFields }
          }
        }
        """ + commentFragment

    static let deleteComment = """
        mutation($id: ID!) { deletePullRequestReviewComment(input: { id: $id }) { clientMutationId } }
        """

    static let submit = """
        mutation($reviewID: ID!, $event: PullRequestReviewEvent!, $body: String) {
          submitPullRequestReview(input: { pullRequestReviewId: $reviewID, event: $event, body: $body }) {
            pullRequestReview { id }
          }
        }
        """

    static let createAndSubmit = """
        mutation($id: ID!, $event: PullRequestReviewEvent!, $body: String) {
          addPullRequestReview(input: { pullRequestId: $id, event: $event, body: $body }) { pullRequestReview { id } }
        }
        """
}
