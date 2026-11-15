import Foundation
import Observation
import SylvraCore

/// State of the PR column.
@MainActor
@Observable
public final class PullRequestScreenModel {
    public enum Tab: String, CaseIterable, Identifiable {
        case overview, files, commits, checks
        public var id: String { rawValue }
    }

    public enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    public private(set) var detail: PullRequestDetail?
    public private(set) var loadState: LoadState = .idle
    public var tab: Tab = .overview

    private let loader: any PullRequestDetailLoading

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
