import Foundation

/// Loads the pull requests shown in the inbox.
public protocol InboxLoading: Sendable {
    func loadInbox(scope: InboxScope) async throws -> InboxSnapshot
}

/// Finds repositories to add to the inbox.
public protocol RepositorySearching: Sendable {
    /// Repositories matching a GitHub search text (e.g. `org:acme billing`).
    func searchRepositories(matching text: String) async throws -> [InboxRepository]
}
