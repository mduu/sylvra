import Foundation
import Platform
import SylvraCore

/// Open pull requests of a repository via GitHub search (paged, newest activity first).
public struct GitHubRepositoryPullRequestLoader: RepositoryPullRequestLoading {
    private let client: GitHubClient
    private let pageSize: Int

    public init(client: GitHubClient, pageSize: Int = 40) {
        self.client = client
        self.pageSize = pageSize
    }

    public func openPullRequestCounts(for repositories: [InboxRepository]) async throws -> [String: Int] {
        guard !repositories.isEmpty else { return [:] }
        let response = try await client.graphQL(
            Self.countQuery(count: repositories.count),
            variables: GitHubInboxLoader.variables(repositories.map { "is:pr is:open repo:\($0.fullName)" }),
            as: [String: CountResult].self)
        var counts: [String: Int] = [:]
        for (index, repository) in repositories.enumerated() {
            counts[repository.id] = response["s\(index)"]?.issueCount
        }
        return counts
    }

    public func loadPullRequests(
        in repository: InboxRepository, matching text: String, excludingAuthors excludedAuthors: [String],
        after cursor: String?
    ) async throws -> RepositoryPullRequestPage {
        let response = try await client.graphQL(
            Self.pageQuery(pageSize: pageSize),
            variables: [
                "q": .string(Self.searchQuery(repository: repository, text: text, excludedAuthors: excludedAuthors)),
                "after": cursor.map(GraphQLValue.string) ?? .null,
            ],
            as: PageResponse.self)
        let search = response.search
        return RepositoryPullRequestPage(
            pullRequests: search.nodes.compactMap { $0?.summary },
            totalCount: search.issueCount,
            nextCursor: search.pageInfo.hasNextPage ? search.pageInfo.endCursor : nil)
    }

    /// Search text for a repository; hidden authors are excluded while the query stays below GitHub's limit.
    static func searchQuery(repository: InboxRepository, text: String, excludedAuthors: [String]) -> String {
        var query = "is:pr is:open archived:false sort:updated-desc repo:\(repository.fullName)"
        let text = text.trimmingCharacters(in: .whitespaces)
        if !text.isEmpty { query += " \(text)" }
        for author in excludedAuthors {
            let qualifier = " -author:\(author)"
            guard query.count + qualifier.count <= InboxScope.maxQueryLength else { break }
            query += qualifier
        }
        return query
    }

    static func countQuery(count: Int) -> String {
        let indices = 0..<count
        let parameters = indices.map { "$q\($0): String!" }.joined(separator: ", ")
        let searches = indices.map { "s\($0): search(query: $q\($0), type: ISSUE, first: 0) { issueCount }" }
        return "query(\(parameters)) {\n\(searches.joined(separator: "\n"))\n}"
    }

    static func pageQuery(pageSize: Int) -> String {
        """
        query($q: String!, $after: String) {
          search(query: $q, type: ISSUE, first: \(pageSize), after: $after) {
            issueCount
            pageInfo { hasNextPage endCursor }
            nodes { ...PR }
          }
        }

        """ + PullRequestNode.fragment
    }

    private struct CountResult: Decodable, Sendable {
        let issueCount: Int
    }

    private struct PageResponse: Decodable, Sendable {
        let search: Search
        struct Search: Decodable, Sendable {
            let issueCount: Int
            let pageInfo: PageInfo
            let nodes: [PullRequestNode?]
        }
        struct PageInfo: Decodable, Sendable {
            let hasNextPage: Bool
            let endCursor: String?
        }
    }
}
