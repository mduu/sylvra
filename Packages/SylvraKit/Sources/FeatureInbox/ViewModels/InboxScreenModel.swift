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

    private let loader: any InboxLoading
    private let cache: JSONCache?

    /// - Parameter cache: shows the last loaded inbox immediately at launch (`nil` in demo mode and tests).
    public init(loader: any InboxLoading, cache: JSONCache? = nil) {
        self.loader = loader
        self.cache = cache
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
            snapshot = try await loader.loadInbox()
            loadState = .loaded
            cache?.save(snapshot, key: "inbox")
        } catch {
            loadState = .failed(Self.message(for: error))
        }
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
