import Foundation
import Observation
import Platform
import SylvraCore

/// State of the inbox screen.
@MainActor
@Observable
public final class InboxScreenModel {
    public enum LoadState: Equatable {
        case idle
        case loading
        case loaded
        case failed(String)
    }

    public private(set) var snapshot = InboxSnapshot(sections: [:], loadedAt: .distantPast)
    public private(set) var loadState: LoadState = .idle
    public var searchText = ""
    /// Repositories the broad sections search (persisted; empty = all).
    public private(set) var scope: InboxScope
    /// Shows the sheet for choosing the inbox repositories.
    public var isChoosingRepositories = false

    private let loader: any InboxLoading
    private let cache: JSONCache?
    private let defaults: UserDefaults?
    /// Repository search for the chooser; `nil` hides it.
    public let repositorySearcher: (any RepositorySearching)?

    private static let logger = SylvraLog.logger("inbox")
    static let scopeKey = "inbox.scope"

    /// - Parameters:
    ///   - cache: shows the last loaded inbox immediately at launch (`nil` in demo mode and tests).
    ///   - defaults: stores the chosen repositories (`nil` in tests: nothing is persisted).
    public init(
        loader: any InboxLoading, cache: JSONCache? = nil, repositorySearcher: (any RepositorySearching)? = nil,
        defaults: UserDefaults? = nil
    ) {
        self.loader = loader
        self.cache = cache
        self.repositorySearcher = repositorySearcher
        self.defaults = defaults
        scope =
            defaults?.data(forKey: Self.scopeKey).flatMap { try? JSONDecoder().decode(InboxScope.self, from: $0) }
            ?? .all
        if let cached = cache?.load(InboxSnapshot.self, key: "inbox") {
            snapshot = cached
            loadState = .loaded
        }
    }

    /// Sections with the PRs matching the current search.
    /// Empty sections are hidden to keep the sidebar calm.
    public var visibleSections: [(section: InboxSection, pullRequests: [PullRequestSummary])] {
        InboxSection.allCases.compactMap { section in
            let pullRequests = snapshot.pullRequests(in: section).filter(matchesSearch)
            return pullRequests.isEmpty ? nil : (section, pullRequests)
        }
    }

    /// The latest summary of a PR in any section.
    public func summary(for id: PullRequestID) -> PullRequestSummary? {
        snapshot.sections.values.lazy.flatMap { $0 }.first { $0.id == id }
    }

    public func refresh() async {
        if snapshot.isEmpty { loadState = .loading }
        do {
            snapshot = try await loader.loadInbox(scope: scope)
            loadState = .loaded
            cache?.save(snapshot, key: "inbox")
        } catch is CancellationError {
            if snapshot.isEmpty { loadState = .idle }
        } catch {
            Self.logger.error("Loading the inbox failed: \(String(describing: error), privacy: .public)")
            loadState = .failed(Self.message(for: error))
        }
    }

    // MARK: - Repositories

    public func addRepository(_ repository: InboxRepository) async {
        guard !scope.repositories.contains(repository) else { return }
        var repositories = scope.repositories + [repository]
        repositories.sort { $0.id < $1.id }
        await setScope(InboxScope(repositories: repositories))
    }

    public func removeRepository(_ repository: InboxRepository) async {
        await setScope(InboxScope(repositories: scope.repositories.filter { $0 != repository }))
    }

    /// Back to all repositories.
    public func showAllRepositories() async {
        await setScope(.all)
    }

    /// Repositories that appear in the current inbox but aren't chosen yet (suggestions for the chooser).
    public var suggestedRepositories: [InboxRepository] {
        var seen = Set(scope.repositories)
        return snapshot.sections.values.flatMap { $0 }
            .sorted { $0.updatedAt > $1.updatedAt }
            .map { InboxRepository(owner: $0.id.owner, name: $0.id.repository) }
            .filter { seen.insert($0).inserted }
    }

    private func setScope(_ newScope: InboxScope) async {
        guard newScope != scope else { return }
        scope = newScope
        if let data = try? JSONEncoder().encode(newScope) { defaults?.set(data, forKey: Self.scopeKey) }
        await refresh()
    }

    /// Refreshes periodically while the task is alive (cancelled with the view).
    public func keepRefreshing(every interval: Duration = .seconds(120)) async {
        while !Task.isCancelled {
            await refresh()
            try? await Task.sleep(for: interval)
        }
    }

    private func matchesSearch(_ pullRequest: PullRequestSummary) -> Bool {
        let query = searchText.trimmingCharacters(in: .whitespaces)
        guard !query.isEmpty else { return true }
        return [pullRequest.title, pullRequest.id.description, pullRequest.author.login, pullRequest.headRefName]
            .contains { $0.localizedCaseInsensitiveContains(query) }
    }

    private static func message(for error: any Error) -> String {
        if let localized = error as? LocalizedError, let description = localized.errorDescription {
            return description
        }
        return String(describing: error)
    }
}
