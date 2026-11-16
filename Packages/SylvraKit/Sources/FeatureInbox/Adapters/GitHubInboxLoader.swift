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

    public func loadInbox() async throws -> InboxSnapshot {
        let client = client
        let pageSize = pageSize
        let sections = try await withThrowingTaskGroup(of: (InboxSection, [PullRequestSummary]).self) { group in
            for section in InboxSection.allCases {
                group.addTask {
                    let response = try await client.graphQL(
                        Self.query(for: section, pageSize: pageSize), as: [String: SearchResult].self)
                    return (section, response[section.rawValue]?.nodes.compactMap { $0?.summary } ?? [])
                }
            }
            var sections: [InboxSection: [PullRequestSummary]] = [:]
            for try await (section, pullRequests) in group { sections[section] = pullRequests }
            return sections
        }
        return InboxSnapshot(sections: sections)
    }

    static func query(for section: InboxSection, pageSize: Int) -> String {
        let query = section.searchQuery()
        return """
            query {
            \(section.rawValue): search(query: "\(query)", type: ISSUE, first: \(pageSize)) { nodes { ...PR } }
            }

            """ + PullRequestNode.fragment
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
          author { login avatarUrl ... on User { name } }
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
    let author: GitHubActorNode?
    let commits: Commits?

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
            mergeability: mergeable.flatMap(Mergeability.init(rawValue:)) ?? .unknown
        )
    }
}
