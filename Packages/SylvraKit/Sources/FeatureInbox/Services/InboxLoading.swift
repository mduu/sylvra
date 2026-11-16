import Foundation
import SylvraCore

/// Loads the pull requests shown in the inbox.
public protocol InboxLoading: Sendable {
    func loadInbox(scope: InboxScope) async throws -> InboxSnapshot
}

/// Finds repositories to add to the inbox.
public protocol RepositorySearching: Sendable {
    /// Repositories matching a GitHub search text (e.g. `org:acme billing`).
    func searchRepositories(matching text: String) async throws -> [InboxRepository]
}

/// Open pull requests of one repository, independent of the user's involvement.
public protocol RepositoryPullRequestLoading: Sendable {
    /// Number of open pull requests per repository (keyed by `InboxRepository.id`).
    func openPullRequestCounts(for repositories: [InboxRepository]) async throws -> [String: Int]

    /// One page of open pull requests, most recently updated first.
    /// - Parameters:
    ///   - text: GitHub search text (title, body, `author:x` …); empty for all.
    ///   - excludedAuthors: hidden authors, filtered on the server so pages stay full.
    ///   - cursor: `nextCursor` of the previous page; `nil` for the first page.
    func loadPullRequests(
        in repository: InboxRepository, matching text: String, excludingAuthors excludedAuthors: [String],
        after cursor: String?
    ) async throws -> RepositoryPullRequestPage
}

/// A page of a repository's open pull requests.
public struct RepositoryPullRequestPage: Sendable, Equatable {
    public var pullRequests: [PullRequestSummary]
    public var totalCount: Int
    /// Cursor for the next page; `nil` when everything is loaded.
    public var nextCursor: String?

    public init(pullRequests: [PullRequestSummary], totalCount: Int, nextCursor: String?) {
        self.pullRequests = pullRequests
        self.totalCount = totalCount
        self.nextCursor = nextCursor
    }
}
