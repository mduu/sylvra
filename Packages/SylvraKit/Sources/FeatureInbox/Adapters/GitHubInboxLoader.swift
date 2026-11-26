import Foundation
import Platform
import SylvraCore

/// Loads the inbox sections with one GraphQL search per section, in parallel.
///
/// A single combined query is too heavy for accounts with many pull requests: GitHub answers with
/// 502 once a query exceeds its time limit, so each section gets its own small request.
public struct GitHubInboxLoader: InboxLoading {
    private let client: GitHubClient
    private let pageSize: Int

    public init(client: GitHubClient, pageSize: Int = 30) {
        self.client = client
        self.pageSize = pageSize
    }

    public func loadInbox(scope: InboxScope) async throws -> InboxSnapshot {
        let client = client
        let pageSize = pageSize
        let now = Date.now
        // In parallel with the sections (asked after them, it added a round trip to every refresh).
        async let viewer = try? client.viewer()
        let loaded = try await withThrowingTaskGroup(of: LoadedSection.self) { group in
            for section in InboxSection.allCases {
                let searches = scope.searchQueries(for: section, now: now)
                group.addTask {
                    let response = try await client.graphQL(
                        Self.query(searchCount: searches.count, pageSize: pageSize),
                        variables: Self.variables(searches),
                        as: [String: SearchResult].self)
                    return LoadedSection(
                        section: section, pullRequests: Self.merge(response, limit: pageSize),
                        nodeIDs: Self.nodeIDs(in: response))
                }
            }
            var loaded: [LoadedSection] = []
            for try await result in group { loaded.append(result) }
            return loaded
        }
        var sections: [InboxSection: [PullRequestSummary]] = [:]
        var nodeIDs: [String: PullRequestID] = [:]
        for result in loaded {
            sections[result.section] = result.pullRequests
            nodeIDs.merge(result.nodeIDs) { first, _ in first }
        }
        let native = await stackMemberships(nodeIDs)
        let isRestricted = await !client.ssoRestrictedOrganizations.isEmpty
        let login = await viewer?.login
        return InboxSnapshot(
            sections: InboxStacks.annotate(sections, native: native), isRestrictedBySSO: isRestricted ? true : nil,
            viewerLogin: login)
    }

    /// GitHub's stacks of the listed pull requests, in their own query: the stack fields are a preview API, and
    /// should GitHub change them (or a GitHub Enterprise Server lack them) the inbox must still load. Empty then.
    private func stackMemberships(_ nodeIDs: [String: PullRequestID]) async -> [PullRequestID: StackMembership] {
        var result: [PullRequestID: StackMembership] = [:]
        let ids = nodeIDs.keys.sorted()
        for start in stride(from: 0, to: ids.count, by: 100) {
            let chunk = Array(ids[start..<min(start + 100, ids.count)])
            guard
                let response = try? await client.graphQL(
                    Self.stackQuery, variables: ["ids": .array(chunk.map { .string($0) })], as: StackNodes.self)
            else { return result }
            for node in response.nodes.compactMap({ $0 }) {
                guard let id = node.id.flatMap({ nodeIDs[$0] }), let stack = node.stack,
                    let position = node.stackEntry?.position
                else { continue }
                result[id] = StackMembership(id: "github:\(stack.id)", position: position, size: stack.size)
            }
        }
        return result
    }

    static let stackQuery = """
        query($ids: [ID!]!) {
          nodes(ids: $ids) { ... on PullRequest { id stack { id size } stackEntry { position } } }
        }
        """

    /// GitHub node IDs of the found pull requests.
    fileprivate static func nodeIDs(in response: [String: SearchResult]) -> [String: PullRequestID] {
        var result: [String: PullRequestID] = [:]
        for node in response.values.flatMap({ $0.nodes.compactMap { $0 } }) {
            if let nodeID = node.id, let summary = node.summary { result[nodeID] = summary.id }
        }
        return result
    }

    /// One aliased search per query (`s0`, `s1` …); search texts are passed as variables.
    static func query(searchCount: Int, pageSize: Int) -> String {
        let indices = 0..<max(searchCount, 1)
        let parameters = indices.map { "$q\($0): String!" }.joined(separator: ", ")
        let searches = indices.map {
            "s\($0): search(query: $q\($0), type: ISSUE, first: \(pageSize)) { nodes { ...PR } }"
        }
        return "query(\(parameters)) {\n\(searches.joined(separator: "\n"))\n}\n" + PullRequestNode.fragment
    }

    static func variables(_ searches: [String]) -> [String: GraphQLValue] {
        Dictionary(uniqueKeysWithValues: searches.enumerated().map { ("q\($0.offset)", .string($0.element)) })
    }

    /// Combines the chunks of a section: deduplicated, most recently updated first.
    fileprivate static func merge(_ response: [String: SearchResult], limit: Int) -> [PullRequestSummary] {
        var seen = Set<PullRequestID>()
        let all = response.keys.sorted().flatMap { response[$0]?.nodes.compactMap { $0?.summary } ?? [] }
        return all.filter { seen.insert($0.id).inserted }
            .sorted { $0.updatedAt > $1.updatedAt }
            .prefix(limit)
            .map { $0 }
    }
}

/// Repository search for adding repositories to the inbox.
public struct GitHubRepositorySearcher: RepositorySearching {
    private let client: GitHubClient

    public init(client: GitHubClient) {
        self.client = client
    }

    public func searchRepositories(matching text: String) async throws -> [InboxRepository] {
        let text = text.trimmingCharacters(in: .whitespacesAndNewlines)
        guard !text.isEmpty else { return [] }
        let response = try await client.graphQL(
            Self.query, variables: ["q": .string("\(text) archived:false fork:true")], as: RepositorySearch.self)
        return response.search.nodes.compactMap { node in
            guard let node else { return nil }
            return InboxRepository(owner: node.owner.login, name: node.name, summary: node.description)
        }
    }

    static let query = """
        query($q: String!) {
          search(query: $q, type: REPOSITORY, first: 20) {
            nodes { ... on Repository { name description owner { login } } }
          }
        }
        """

    private struct RepositorySearch: Decodable, Sendable {
        let search: Search
        struct Search: Decodable, Sendable { let nodes: [Node?] }
        struct Node: Decodable, Sendable {
            let name: String
            let description: String?
            let owner: Owner
        }
        struct Owner: Decodable, Sendable { let login: String }
    }
}

private struct SearchResult: Decodable, Sendable {
    let nodes: [PullRequestNode?]
}

/// One section's pull requests and their GitHub node IDs (for the stack query).
private struct LoadedSection: Sendable {
    let section: InboxSection
    let pullRequests: [PullRequestSummary]
    let nodeIDs: [String: PullRequestID]
}

private struct StackNodes: Decodable, Sendable {
    let nodes: [Node?]
    struct Node: Decodable, Sendable {
        let id: String?
        let stack: Stack?
        let stackEntry: Entry?
    }
    struct Stack: Decodable, Sendable {
        let id: String
        let size: Int
    }
    struct Entry: Decodable, Sendable { let position: Int }
}

/// GraphQL fragment + decoding for a pull request list item.
struct PullRequestNode: Decodable, Sendable {
    static let fragment = """
        fragment PR on PullRequest {
          id number title url isDraft createdAt updatedAt additions deletions
          headRefName baseRefName reviewDecision mergeable
          repository { name owner { login } }
          author { __typename login avatarUrl ... on User { name } }
          commits(last: 1) { nodes { commit { committedDate statusCheckRollup { state } } } }
          viewerDidAuthor
          comments(last: 10) { totalCount nodes { createdAt viewerDidAuthor author { __typename login } } }
          reviewThreads { totalCount }
          reviews(last: 10) { nodes { submittedAt state viewerDidAuthor author { __typename login } } }
        }
        """

    /// GitHub node ID.
    let id: String?
    let number: Int?
    let title: String?
    let url: URL?
    let isDraft: Bool?
    let createdAt: Date?
    let updatedAt: Date?
    let additions: Int?
    let deletions: Int?
    let headRefName: String?
    let baseRefName: String?
    let reviewDecision: String?
    let mergeable: String?
    let repository: Repository?
    let author: AuthorNode?
    let commits: Commits?
    let viewerDidAuthor: Bool?
    let comments: Activities?
    let reviews: Activities?
    let reviewThreads: Count?

    struct Count: Decodable, Sendable { let totalCount: Int }

    /// Comments or reviews; `date` is `createdAt` or `submittedAt` (pending reviews have none).
    struct Activities: Decodable, Sendable {
        let totalCount: Int?
        let nodes: [Activity?]
        struct Activity: Decodable, Sendable {
            let createdAt: Date?
            let submittedAt: Date?
            let viewerDidAuthor: Bool?
            let author: Author?
            /// Reviews only: `APPROVED`, `CHANGES_REQUESTED`, `COMMENTED` …
            let state: String?
            var date: Date? { submittedAt ?? createdAt }
            var isByBot: Bool { author?.typename == "Bot" }
        }
        struct Author: Decodable, Sendable {
            let typename: String?
            let login: String?
            enum CodingKeys: String, CodingKey { case typename = "__typename", login }
        }
    }

    struct AuthorNode: Decodable, Sendable {
        let typename: String?
        let login: String
        let name: String?
        let avatarUrl: URL?

        enum CodingKeys: String, CodingKey {
            case typename = "__typename", login, name, avatarUrl
        }

        var userRef: UserRef { UserRef(login: login, name: name, avatarURL: avatarUrl) }
    }

    struct Repository: Decodable, Sendable {
        let name: String
        let owner: Owner
        struct Owner: Decodable, Sendable { let login: String }
    }

    struct Commits: Decodable, Sendable {
        let nodes: [Node?]
        struct Node: Decodable, Sendable { let commit: Commit }
        struct Commit: Decodable, Sendable {
            let committedDate: Date?
            let statusCheckRollup: Rollup?
        }
        struct Rollup: Decodable, Sendable { let state: String }
    }

    /// Converts to the domain model; `nil` for non-PR search results.
    var summary: PullRequestSummary? {
        guard let number, let title, let repository, let createdAt, let updatedAt else { return nil }
        let rollup = commits?.nodes.last??.commit.statusCheckRollup?.state.lowercased()
        var summary = PullRequestSummary(
            id: PullRequestID(owner: repository.owner.login, repository: repository.name, number: number),
            title: title,
            author: author?.userRef ?? UserRef(login: "ghost"),
            url: url,
            isDraft: isDraft ?? false,
            createdAt: createdAt,
            updatedAt: updatedAt,
            additions: additions ?? 0,
            deletions: deletions ?? 0,
            headRefName: headRefName ?? "",
            baseRefName: baseRefName ?? "",
            checkState: rollup.flatMap(CheckState.init(rawValue:)) ?? .none,
            reviewDecision: reviewDecision.flatMap(ReviewDecision.init(rawValue:)) ?? .none,
            mergeability: mergeable.flatMap(Mergeability.init(rawValue:)) ?? .unknown,
            authorIsBot: author?.typename == "Bot",
            viewerActivity: viewerActivity,
            commentCount: commentCount
        )
        summary.authorFeedback = authorFeedback
        return summary
    }

    /// On the viewer's own pull request: the latest review or comment by someone else (bots don't count).
    var authorFeedback: AuthorFeedback? {
        guard viewerDidAuthor == true else { return nil }
        func others(_ activities: Activities?) -> [Activities.Activity] {
            (activities?.nodes ?? []).compactMap { $0 }.filter { $0.viewerDidAuthor != true && !$0.isByBot }
        }
        let comments = others(comments).compactMap { activity in
            activity.date.map { AuthorFeedback(kind: .comment, at: $0, by: activity.author?.login) }
        }
        let reviews = others(reviews).compactMap { activity -> AuthorFeedback? in
            guard let date = activity.date else { return nil }
            let kind: AuthorFeedback.Kind =
                switch activity.state {
                case "APPROVED": .approved
                case "CHANGES_REQUESTED": .changesRequested
                default: .reviewed
                }
            return AuthorFeedback(kind: kind, at: date, by: activity.author?.login)
        }
        return (comments + reviews).max { $0.at < $1.at }
    }

    /// Conversation comments plus code threads (`nil` when the query didn't ask).
    var commentCount: Int? {
        guard comments?.totalCount != nil || reviewThreads != nil else { return nil }
        return (comments?.totalCount ?? 0) + (reviewThreads?.totalCount ?? 0)
    }

    /// The reviewer's last review or comment against everyone else's latest commit, review or comment.
    var viewerActivity: ViewerActivity? {
        guard viewerDidAuthor != true, comments != nil || reviews != nil else { return nil }
        let activities = (comments?.nodes ?? []) + (reviews?.nodes ?? [])
        let mine = activities.compactMap { $0?.viewerDidAuthor == true ? $0?.date : nil }.max()
        let others = activities.compactMap { activity -> Date? in
            guard let activity, activity.viewerDidAuthor != true, !activity.isByBot else { return nil }
            return activity.date
        }
        let lastCommit = commits?.nodes.last??.commit.committedDate
        return ViewerActivity(lastActionAt: mine, othersLastActivityAt: (others + [lastCommit].compactMap { $0 }).max())
    }
}
