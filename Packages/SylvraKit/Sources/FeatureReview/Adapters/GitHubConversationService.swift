import Foundation
import Platform
import SylvraCore

/// The pull request conversation via GitHub GraphQL (`IssueComment` and `PullRequestReview`).
public struct GitHubConversationService: ConversationService {
    private let client: GitHubClient

    public init(client: GitHubClient) {
        self.client = client
    }

    public func loadConversation(for id: PullRequestID) async throws -> Conversation {
        let response = try await client.graphQL(
            ConversationQueries.load,
            variables: ["owner": .string(id.owner), "name": .string(id.repository), "number": .int(id.number)],
            as: ConversationResponse.self
        )
        guard let pullRequest = response.repository?.pullRequest else {
            throw GitHubError.graphQL(["Pull request \(id) not found"])
        }
        return pullRequest.conversation
    }

    public func addComment(pullRequestNodeID: String, body: String) async throws -> ConversationEntry {
        let response = try await client.graphQL(
            ConversationQueries.addComment, variables: ["id": .string(pullRequestNodeID), "body": .string(body)],
            as: AddCommentResponse.self)
        guard let node = response.addComment?.commentEdge?.node else {
            throw GitHubError.decoding("addComment returned no comment")
        }
        return ConversationEntry(kind: .comment, comment: node.comment)
    }

    public func updateBody(of entry: ConversationEntry, to body: String) async throws -> String {
        let variables: [String: GraphQLValue] = ["id": .string(entry.id), "body": .string(body)]
        switch entry.kind {
        case .comment:
            let response = try await client.graphQL(
                ConversationQueries.updateComment, variables: variables, as: UpdateIssueCommentResponse.self)
            guard let comment = response.updateIssueComment?.issueComment else {
                throw GitHubError.decoding("updateIssueComment returned no comment")
            }
            return comment.body
        case .review:
            let response = try await client.graphQL(
                ConversationQueries.updateReview, variables: variables, as: UpdateReviewResponse.self)
            guard let review = response.updatePullRequestReview?.pullRequestReview else {
                throw GitHubError.decoding("updatePullRequestReview returned no review")
            }
            return review.body
        }
    }

    public func deleteComment(id: String) async throws {
        _ = try await client.graphQL(
            ConversationQueries.deleteComment, variables: ["id": .string(id)], as: EmptyResponse.self)
    }

    public func setReaction(_ reaction: Reaction, added: Bool, subjectID: String) async throws {
        _ = try await client.graphQL(
            added ? ReviewQueries.addReaction : ReviewQueries.removeReaction,
            variables: ["id": .string(subjectID), "content": .string(reaction.rawValue)], as: EmptyResponse.self)
    }
}

// MARK: - Queries

enum ConversationQueries {
    static let commonFields = """
        id body createdAt url viewerCanUpdate viewerCanDelete
        author { login avatarUrl ... on User { name } }
        reactionGroups { content viewerHasReacted reactors { totalCount } }
        """

    static let commentFragment = "fragment IssueCommentFields on IssueComment { \(commonFields) }\n"
    static let reviewFragment = "fragment ReviewFields on PullRequestReview { state \(commonFields) }\n"

    /// The latest 100 comments and reviews (pending reviews are the viewer's own draft and stay out).
    static let load = """
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              id
              comments(last: 100) { nodes { ...IssueCommentFields } }
              reviews(last: 100, states: [APPROVED, CHANGES_REQUESTED, COMMENTED, DISMISSED]) {
                nodes { ...ReviewFields }
              }
            }
          }
        }
        """ + commentFragment + reviewFragment

    static let addComment = """
        mutation($id: ID!, $body: String!) {
          addComment(input: { subjectId: $id, body: $body }) { commentEdge { node { ...IssueCommentFields } } }
        }
        """ + commentFragment

    static let updateComment = """
        mutation($id: ID!, $body: String!) {
          updateIssueComment(input: { id: $id, body: $body }) { issueComment { body } }
        }
        """

    static let updateReview = """
        mutation($id: ID!, $body: String!) {
          updatePullRequestReview(input: { pullRequestReviewId: $id, body: $body }) { pullRequestReview { body } }
        }
        """

    static let deleteComment = """
        mutation($id: ID!) { deleteIssueComment(input: { id: $id }) { clientMutationId } }
        """
}

// MARK: - Responses

struct ConversationResponse: Decodable, Sendable {
    let repository: Repository?
    struct Repository: Decodable, Sendable { let pullRequest: PullRequestNode? }

    struct PullRequestNode: Decodable, Sendable {
        let id: String
        let comments: Nodes<CommentNode>
        let reviews: Nodes<CommentNode>

        /// Comments plus reviews; a review that only carries code comments (no text, just "commented")
        /// says nothing here and is left out.
        var conversation: Conversation {
            let comments = self.comments.values.map { ConversationEntry(kind: .comment, comment: $0.comment) }
            let reviews = self.reviews.values.compactMap { node -> ConversationEntry? in
                guard let state = node.state.flatMap(ConversationEntry.ReviewState.init(rawValue:)) else { return nil }
                let entry = ConversationEntry(kind: .review(state), comment: node.comment)
                return entry.isEvent && state == .commented ? nil : entry
            }
            return Conversation(pullRequestNodeID: id, entries: comments + reviews)
        }
    }
}

struct AddCommentResponse: Decodable, Sendable {
    let addComment: Payload?
    struct Payload: Decodable, Sendable { let commentEdge: Edge? }
    struct Edge: Decodable, Sendable { let node: CommentNode? }
}

struct UpdateIssueCommentResponse: Decodable, Sendable {
    let updateIssueComment: Payload?
    struct Payload: Decodable, Sendable { let issueComment: Body? }
}

struct UpdateReviewResponse: Decodable, Sendable {
    let updatePullRequestReview: Payload?
    struct Payload: Decodable, Sendable { let pullRequestReview: Body? }
}

struct Body: Decodable, Sendable {
    let body: String
}
