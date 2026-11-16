import Foundation
import Observation
import Platform
import SylvraCore

/// All open pull requests of one repository, loaded page by page (search runs on GitHub).
@MainActor
@Observable
public final class RepositoryBrowserModel {
    public enum LoadState: Equatable {
        case loading
        case loaded
        case failed(String)
    }

    public let repository: InboxRepository
    public private(set) var pullRequests: [PullRequestSummary] = []
    public private(set) var totalCount = 0
    public private(set) var loadState: LoadState = .loading
    public private(set) var isLoadingMore = false
    /// Search text of the loaded list (the sidebar search, sent to GitHub).
    public private(set) var searchText = ""

    private var nextCursor: String?
    private let loader: any RepositoryPullRequestLoading
    private static let logger = SylvraLog.logger("inbox")

    public init(repository: InboxRepository, loader: any RepositoryPullRequestLoading) {
        self.repository = repository
        self.loader = loader
    }

    public var canLoadMore: Bool { nextCursor != nil }

    /// Loads the first page for a search text (empty = all open pull requests).
    public func load(matching text: String, excludingAuthors excludedAuthors: [String]) async {
        searchText = text
        if pullRequests.isEmpty { loadState = .loading }
        do {
            let page = try await loader.loadPullRequests(
                in: repository, matching: text, excludingAuthors: excludedAuthors, after: nil)
            guard text == searchText else { return }
            pullRequests = page.pullRequests
            totalCount = page.totalCount
            nextCursor = page.nextCursor
            loadState = .loaded
        } catch is CancellationError {
        } catch {
            Self.logger.error(
                "Loading \(self.repository.fullName, privacy: .public) failed: \(String(describing: error), privacy: .public)"
            )
            loadState = .failed((error as? LocalizedError)?.errorDescription ?? String(describing: error))
        }
    }

    public func loadMore(excludingAuthors excludedAuthors: [String]) async {
        guard let cursor = nextCursor, !isLoadingMore else { return }
        isLoadingMore = true
        defer { isLoadingMore = false }
        let text = searchText
        do {
            let page = try await loader.loadPullRequests(
                in: repository, matching: text, excludingAuthors: excludedAuthors, after: cursor)
            guard text == searchText else { return }
            let known = Set(pullRequests.map(\.id))
            pullRequests += page.pullRequests.filter { !known.contains($0.id) }
            nextCursor = page.nextCursor
        } catch {
            Self.logger.error("Loading more pull requests failed: \(String(describing: error), privacy: .public)")
        }
    }
}
