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
        let sections = try await withThrowingTaskGroup(of: (InboxSection, [PullRequestSummary]).self) { group in
            for section in InboxSection.allCases {
                let searches = scope.searchQueries(for: section, now: now)
                group.addTask {
                    let response = try await client.graphQL(
                        Self.query(searchCount: searches.count, pageSize: pageSize),
                        variables: Self.variables(searches),
                        as: [String: SearchResult].self)
                    return (section, Self.merge(response, limit: pageSize))
                }
            }
            var sections: [InboxSection: [PullRequestSummary]] = [:]
            for try await (section, pullRequests) in group { sections[section] = pullRequests }
            return sections
        }
        let isRestricted = await !client.ssoRestrictedOrganizations.isEmpty
        let viewer = try? await client.viewer()
        return InboxSnapshot(
            sections: sections, isRestrictedBySSO: isRestricted ? true : nil, viewerLogin: viewer?.login)
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

/// GraphQL fragment + decoding for a pull request list item.
struct PullRequestNode: Decodable, Sendable {
    static let fragment = """
        fragment PR on PullRequest {
          number title url isDraft createdAt updatedAt additions deletions
          headRefName baseRefName reviewDecision mergeable
          repository { name owner { login } }
          author { __typename login avatarUrl ... on User { name } }
          commits(last: 1) { nodes { commit { statusCheckRollup { state } } } }
        }
        """

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
        struct Commit: Decodable, Sendable { let statusCheckRollup: Rollup? }
        struct Rollup: Decodable, Sendable { let state: String }
    }

    /// Converts to the domain model; `nil` for non-PR search results.
    var summary: PullRequestSummary? {
        guard let number, let title, let repository, let createdAt, let updatedAt else { return nil }
        let rollup = commits?.nodes.last??.commit.statusCheckRollup?.state.lowercased()
        return PullRequestSummary(
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
            authorIsBot: author?.typename == "Bot"
        )
    }
}
