import Foundation
import Observation
import Platform
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
    /// The stack around the pull request (`nil`: none, or not loaded yet).
    public private(set) var stack: StackStatus?
    public var tab: Tab = .overview
    /// Which section of the Comments tab is shown.
    public var discussionFilter: DiscussionFilter = .conversation
    /// The check whose report is shown (sheet).
    public var openedCheck: PullRequestDetail.CheckRun?

    private let loader: any PullRequestDetailLoading
    private static let logger = SylvraLog.logger("pullRequest")
    /// Resolves or reopens a code thread on GitHub (wired by the app; `nil` hides *Resolve*). `false` on failure.
    @ObservationIgnored public var resolveThread: ((_ id: String, _ resolved: Bool) async -> Bool)?

    /// Shows a thread as resolved or open right away (after a change here or in the diff).
    public func markResolved(_ id: String, _ resolved: Bool) {
        guard var detail, let index = detail.discussion.firstIndex(where: { $0.id == id }),
            detail.discussion[index].isResolved != resolved
        else { return }
        detail.discussion[index] = detail.discussion[index].settingResolved(resolved)
        self.detail = detail
    }

    /// *Resolve* / *Unresolve* in the Comments tab: shown at once, undone if GitHub refuses.
    public func toggleResolved(_ item: DiscussionItem) async {
        guard let resolveThread, item.codeLocation != nil else { return }
        let resolved = !item.isResolved
        markResolved(item.id, resolved)
        if await !resolveThread(item.id, resolved) { markResolved(item.id, !resolved) }
    }

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
            stack = nil
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
            return
        }
        await loadStack()
    }

    /// After the details, so the pull request shows without waiting for its neighbours.
    private func loadStack() async {
        guard let detail else { return }
        do {
            let loaded = try await loader.loadStack(for: detail)
            guard !Task.isCancelled, self.detail?.summary.id == detail.summary.id else { return }
            stack = loaded
        } catch {
            // Keeps what was shown: a failing refresh shouldn't make the stack flicker away.
            Self.logger.error("Loading the stack failed: \(String(describing: error), privacy: .public)")
        }
    }
}
