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
    /// Filter preferences (persisted) and temporary quick filters.
    public private(set) var filter = PullRequestFilter()
    /// Shows the sheet for choosing the inbox repositories.
    public var isChoosingRepositories = false

    private let loader: any InboxLoading
    private let cache: JSONCache?
    private let defaults: UserDefaults?
    /// Repository search for the chooser; `nil` hides it.
    public let repositorySearcher: (any RepositorySearching)?
    /// Loads all open pull requests of a repository; `nil` hides the repository list.
    public let repositoryLoader: (any RepositoryPullRequestLoading)?
    /// Open pull requests per repository (`InboxRepository.id`).
    public private(set) var repositoryCounts: [String: Int] = [:]
    /// The repository shown instead of the inbox (`nil` = inbox).
    public private(set) var browser: RepositoryBrowserModel?

    private static let logger = SylvraLog.logger("inbox")
    static let scopeKey = "inbox.scope"
    static let filterKey = "inbox.filter"
    static let collapsedKey = "inbox.collapsedSections"

    /// Sidebar sections the user collapsed (section raw values and `repositories`; persisted).
    public private(set) var collapsedSections: Set<String> = []

    public func isExpanded(_ section: String) -> Bool { !collapsedSections.contains(section) }

    public func setExpanded(_ section: String, _ isExpanded: Bool) {
        if isExpanded { collapsedSections.remove(section) } else { collapsedSections.insert(section) }
        defaults?.set(Array(collapsedSections).sorted(), forKey: Self.collapsedKey)
    }

    /// - Parameters:
    ///   - cache: shows the last loaded inbox immediately at launch (`nil` in demo mode and tests).
    ///   - defaults: stores the chosen repositories (`nil` in tests: nothing is persisted).
    public init(
        loader: any InboxLoading, cache: JSONCache? = nil, repositorySearcher: (any RepositorySearching)? = nil,
        repositoryLoader: (any RepositoryPullRequestLoading)? = nil, defaults: UserDefaults? = nil
    ) {
        self.repositoryLoader = repositoryLoader
        self.loader = loader
        self.cache = cache
        self.repositorySearcher = repositorySearcher
        self.defaults = defaults
        scope =
            defaults?.data(forKey: Self.scopeKey).flatMap { try? JSONDecoder().decode(InboxScope.self, from: $0) }
            ?? .all
        collapsedSections = Set(defaults?.stringArray(forKey: Self.collapsedKey) ?? [])
        filter.preferences =
            defaults?.data(forKey: Self.filterKey).flatMap {
                try? JSONDecoder().decode(InboxFilterPreferences.self, from: $0)
            } ?? InboxFilterPreferences()
        if let cached = cache?.load(InboxSnapshot.self, key: "inbox") {
            snapshot = cached
            loadState = .loaded
        }
    }

    /// Sections with the PRs matching the current search.
    /// Empty sections are hidden to keep the sidebar calm.
    public var visibleSections: [(section: InboxSection, pullRequests: [PullRequestSummary])] {
        InboxSection.allCases.compactMap { section in
            let pullRequests = snapshot.pullRequests(in: section).filter {
                matchesSearch($0) && activeFilter.matches($0)
            }
            return pullRequests.isEmpty ? nil : (section, pullRequests)
        }
    }

    /// The latest summary of a PR in any section.
    public func summary(for id: PullRequestID) -> PullRequestSummary? {
        snapshot.sections.values.lazy.flatMap { $0 }.first { $0.id == id }
            ?? browser?.pullRequests.first { $0.id == id }
    }

    public func refresh() async {
        if snapshot.isEmpty { loadState = .loading }
        do {
            snapshot = try await loader.loadInbox(scope: scope)
            loadState = .loaded
            cache?.save(snapshot, key: "inbox")
            await refreshRepositoryCounts()
        } catch is CancellationError {
            if snapshot.isEmpty { loadState = .idle }
        } catch {
            Self.logger.error("Loading the inbox failed: \(String(describing: error), privacy: .public)")
            loadState = .failed(Self.message(for: error))
        }
    }

    // MARK: - Repository browser

    public func openRepository(_ repository: InboxRepository) {
        guard let repositoryLoader else { return }
        searchText = ""
        browser = RepositoryBrowserModel(repository: repository, loader: repositoryLoader)
    }

    public func closeRepository() {
        searchText = ""
        browser = nil
    }

    /// The browsed repository's pull requests in groups: waiting for you, yours, all others.
    public var browserGroups: [(title: String, pullRequests: [PullRequestSummary])] {
        guard let browser else { return [] }
        let waiting = Set(
            (snapshot.pullRequests(in: .requestedFromMe) + snapshot.pullRequests(in: .myTeams)).map(\.id))
        let viewer = snapshot.viewerLogin?.lowercased()
        let visible = browser.pullRequests.filter(activeFilter.matches)
        let groups: [(String, [PullRequestSummary])] = [
            (String(localized: "Waiting for you"), visible.filter { waiting.contains($0.id) }),
            (String(localized: "Yours"), visible.filter { $0.author.login.lowercased() == viewer }),
            (
                String(localized: "Open"),
                visible.filter { !waiting.contains($0.id) && $0.author.login.lowercased() != viewer }
            ),
        ]
        return groups.filter { !$0.1.isEmpty }.map { (title: $0.0, pullRequests: $0.1) }
    }

    /// Pull requests of the browsed repository the client-side filters hide.
    public var browserHiddenCount: Int {
        browser.map { $0.pullRequests.filter { !activeFilter.matches($0) }.count } ?? 0
    }

    private func refreshRepositoryCounts() async {
        guard let repositoryLoader, !scope.isAll else { return }
        if let counts = try? await repositoryLoader.openPullRequestCounts(for: scope.repositories) {
            repositoryCounts = counts
        }
    }

    // MARK: - Filters

    private var activeFilter: PullRequestFilter {
        var filter = filter
        filter.viewerLogin = snapshot.viewerLogin
        return filter
    }

    /// Pull requests the filters hide (shown as a hint, so an emptier list isn't confusing).
    public var hiddenCount: Int {
        snapshot.sections.values.joined().filter { matchesSearch($0) && !activeFilter.matches($0) }.count
    }

    /// Authors of the loaded pull requests, for the author filter.
    public var authors: [String] {
        let pullRequests = browser?.pullRequests ?? Array(snapshot.sections.values.joined())
        return Array(Set(pullRequests.map(\.author.login))).sorted {
            $0.localizedCaseInsensitiveCompare($1) == .orderedAscending
        }
    }

    public func toggle(_ quickFilter: QuickFilter) {
        if filter.quickFilters.contains(quickFilter) {
            filter.quickFilters.remove(quickFilter)
        } else {
            filter.quickFilters.insert(quickFilter)
        }
    }

    public func showOnly(author: String?) {
        filter.author = author
    }

    public func clearTemporaryFilters() {
        filter.quickFilters = []
        filter.author = nil
    }

    public func updatePreferences(_ change: (inout InboxFilterPreferences) -> Void) {
        change(&filter.preferences)
        if let data = try? JSONEncoder().encode(filter.preferences) { defaults?.set(data, forKey: Self.filterKey) }
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
