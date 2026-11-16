import Foundation
import Observation
import SylvraCore

/// State of the PR column.
@MainActor
@Observable
public final class PullRequestScreenModel {
    public enum Tab: String, CaseIterable, Identifiable {
        case overview, files, commits, checks, comments
        public var id: String { rawValue }
    }

    public enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    public private(set) var detail: PullRequestDetail?
    public private(set) var loadState: LoadState = .idle
    public var tab: Tab = .overview
    /// Which comments the Comments tab shows.
    public var discussionFilter: DiscussionFilter = .all
    /// The check whose report is shown (sheet).
    public var openedCheck: PullRequestDetail.CheckRun?

    private let loader: any PullRequestDetailLoading

    /// GitHub's summary of a check run; commit statuses only have their description.
    public func report(for check: PullRequestDetail.CheckRun) async throws -> CheckReport {
        guard let nodeID = check.nodeID else { return CheckReport(summary: check.statusDescription) }
        return try await loader.loadCheckReport(nodeID: nodeID)
    }

    public init(loader: any PullRequestDetailLoading) {
        self.loader = loader
    }

    public func load(_ id: PullRequestID?) async {
        guard let id else {
            detail = nil
            loadState = .idle
            return
        }
        if detail?.summary.id != id {
            detail = nil
            loadState = .loading
        }
        do {
            let loaded = try await loader.loadDetail(for: id)
            guard !Task.isCancelled else { return }
            detail = loaded
            loadState = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            loadState = .failed(String(describing: error))
        }
    }
}
