import Foundation
import Platform
import SylvraCore

/// Errors while preparing a checkout.
public enum CheckoutError: Error, Equatable, Sendable {
    /// The main clone has uncommitted changes; the user must decide (stash or cancel).
    case dirtyWorkingTree(URL)
    case noLocalClone(String)
}

/// Prepares the PR head locally (see specs/architecture.md §9.2).
public struct CheckoutService: Sendable {
    private let git: GitRunner
    private let locator: RepositoryLocator
    private let storageRoot: URL

    public static var defaultStorageRoot: URL {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        return support.appending(path: "Sylvra")
    }

    public init(
        git: GitRunner = GitRunner(), locator: RepositoryLocator = RepositoryLocator(),
        storageRoot: URL = CheckoutService.defaultStorageRoot
    ) {
        self.git = git
        self.locator = locator
        self.storageRoot = storageRoot
    }

    /// Who uses a worktree.
    public enum Purpose: String, Codable, Sendable {
        /// Opened in the IDE / terminal: one stable path per repository (Rider sees one valid recent project).
        case ide
        /// Read by AI agents: one worktree per PR, so a running review never sees another PR's code.
        case agent
    }

    /// Stable review worktree path per repository — Rider sees one always-valid recent project.
    public func worktreePath(for id: PullRequestID, purpose: Purpose = .ide) -> URL {
        switch purpose {
        case .ide: storageRoot.appending(path: "worktrees/\(id.owner)/\(id.repository)")
        case .agent: storageRoot.appending(path: "agent-worktrees/\(id.owner)/\(id.repository)/pr-\(id.number)")
        }
    }

    /// Clone used for worktrees only when the user has no local clone (blobless, fetched on demand); removed by
    /// `WorktreeCleaner` once no worktree uses it.
    func cacheClonePath(for id: PullRequestID) -> URL {
        storageRoot.appending(path: "repos/\(id.owner)/\(id.repository)")
    }

    /// Checks the PR head out in a review worktree and returns its path.
    /// Git operations on the same repository are serialised (no `index.lock` races between features).
    public func prepareWorktree(for id: PullRequestID, purpose: Purpose) async throws -> URL {
        try await RepositoryLocks.shared.withLock("\(id.owner)/\(id.repository)") {
            try await checkOutWorktree(for: id, purpose: purpose)
        }
    }

    private func checkOutWorktree(for id: PullRequestID, purpose: Purpose) async throws -> URL {
        let worktree = worktreePath(for: id, purpose: purpose)
        let clone = try await attachingToPreferredClone(worktree, preferred: try await cloneForWorktrees(id))
        try await git.run(["fetch", "--quiet", "origin", "pull/\(id.number)/head"], in: clone)
        // FETCH_HEAD is per worktree, so resolve it to a SHA in the clone first.
        let head = try await git.run(["rev-parse", "FETCH_HEAD"], in: clone)
        if FileManager.default.fileExists(atPath: worktree.appending(path: ".git").path) {
            try await git.run(["checkout", "--quiet", "--detach", head], in: worktree)
        } else {
            try FileManager.default.createDirectory(
                at: worktree.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await git.run(["worktree", "prune"], in: clone)
            try await git.run(["worktree", "add", "--quiet", "--detach", worktree.path, head], in: clone)
        }
        // Remembered so the worktree can be listed and cleaned up later (`WorktreeCleaner`).
        await WorktreeRegistry(storageRoot: storageRoot).recordUse(
            path: worktree, purpose: purpose, pullRequest: id, clone: clone)
        return worktree
    }

    /// Checks the PR head out as `review/pr-<n>` in the user's main clone.
    /// Throws `.dirtyWorkingTree` unless the tree is clean or `stashChanges` is `true`.
    /// Returns the clone and the branch that was checked out before (to switch back later).
    public func prepareMainClone(for id: PullRequestID, stashChanges: Bool) async throws -> (
        clone: URL, previousBranch: String?
    ) {
        guard let clone = await locator.localClone(owner: id.owner, name: id.repository) else {
            throw CheckoutError.noLocalClone(id.description)
        }
        if try await !git.isClean(clone) {
            guard stashChanges else { throw CheckoutError.dirtyWorkingTree(clone) }
            try await git.run(
                ["stash", "push", "--include-untracked", "--message", "Sylvra: before reviewing \(id)"], in: clone)
        }
        let previous = try await git.currentBranch(clone)
        try await git.run(["fetch", "--quiet", "origin", "pull/\(id.number)/head"], in: clone)
        try await git.run(["checkout", "--quiet", "-B", "review/pr-\(id.number)", "FETCH_HEAD"], in: clone)
        return (clone, previous)
    }

    /// An existing worktree that belongs to another clone (Sylvra's cache clone, before the user cloned the
    /// repository) is removed so it is recreated in `preferred`, and the cache clone can go away. A worktree with
    /// changed files stays where it is; its own clone is used.
    private func attachingToPreferredClone(_ worktree: URL, preferred: URL) async throws -> URL {
        guard let current = WorktreeCleaner.clone(ofWorktree: worktree),
            Self.canonical(current) != Self.canonical(preferred.path)
        else { return preferred }
        let currentURL = URL(fileURLWithPath: current)
        guard FileManager.default.fileExists(atPath: current) else {
            try? FileManager.default.removeItem(at: worktree)
            return preferred
        }
        if try await !git.isClean(worktree) { return currentURL }
        _ = try? await git.run(["worktree", "remove", "--force", worktree.path], in: currentURL)
        if FileManager.default.fileExists(atPath: worktree.path) { try FileManager.default.removeItem(at: worktree) }
        _ = try? await git.run(["worktree", "prune"], in: currentURL)
        return preferred
    }

    /// Paths compared without symlinks (`/var` vs `/private/var`).
    nonisolated static func canonical(_ path: String) -> String {
        URL(fileURLWithPath: path).resolvingSymlinksInPath().standardizedFileURL.path
    }

    private func cloneForWorktrees(_ id: PullRequestID) async throws -> URL {
        if let local = await locator.localClone(owner: id.owner, name: id.repository) { return local }
        let cache = cacheClonePath(for: id)
        if !FileManager.default.fileExists(atPath: cache.appending(path: ".git").path) {
            try FileManager.default.createDirectory(
                at: cache.deletingLastPathComponent(), withIntermediateDirectories: true)
            try await git.run([
                "clone", "--quiet", "--filter=blob:none", "--no-checkout",
                "https://github.com/\(id.owner)/\(id.repository).git", cache.path,
            ])
        }
        return cache
    }
}

/// Serialises async work per key (one repository at a time).
actor RepositoryLocks {
    static let shared = RepositoryLocks()
    private var tails: [String: Task<Void, Never>] = [:]

    func withLock<T: Sendable>(_ key: String, _ operation: @escaping @Sendable () async throws -> T) async throws -> T {
        let previous = tails[key]
        let task = Task<T, any Error> {
            await previous?.value
            return try await operation()
        }
        tails[key] = Task { _ = try? await task.value }
        return try await task.value
    }
}
