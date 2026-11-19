import Foundation
import SylvraCore

/// A git worktree Sylvra created (see specs/architecture.md §9.2). Kept in `worktrees.json` so the app knows
/// what it owns and can remove it again.
public struct WorktreeRecord: Codable, Hashable, Sendable, Identifiable {
    public var id: String { path }
    public let path: String
    public let purpose: CheckoutService.Purpose
    /// The pull request checked out last (unknown for worktrees found on disk from older versions).
    public var pullRequest: PullRequestID?
    /// The clone the worktree belongs to (the user's local clone or Sylvra's cache clone).
    public var clonePath: String?
    public let createdAt: Date
    public var lastUsedAt: Date

    public init(
        path: String, purpose: CheckoutService.Purpose, pullRequest: PullRequestID?, clonePath: String?,
        createdAt: Date, lastUsedAt: Date
    ) {
        self.path = path
        self.purpose = purpose
        self.pullRequest = pullRequest
        self.clonePath = clonePath
        self.createdAt = createdAt
        self.lastUsedAt = lastUsedAt
    }

    public var url: URL { URL(fileURLWithPath: path) }

    /// `owner/repository`, from the pull request or the path layout (`…/<owner>/<repo>[/pr-<n>]`).
    public var repository: String {
        if let pullRequest { return "\(pullRequest.owner)/\(pullRequest.repository)" }
        let components = url.pathComponents
        let end = purpose == .agent ? components.count - 1 : components.count
        return components[max(end - 2, 0)..<end].joined(separator: "/")
    }

    /// Whether the worktree is in the user's own clone, where Git clients (Fork, Tower, IDEs) list it.
    public func isInUserClone(storageRoot: URL) -> Bool {
        guard let clonePath else { return false }
        return !clonePath.hasPrefix(storageRoot.path + "/")
    }
}
