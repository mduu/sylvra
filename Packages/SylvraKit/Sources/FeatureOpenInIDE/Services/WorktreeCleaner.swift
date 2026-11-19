import Foundation
import Platform
import SylvraCore

/// Errors while removing a worktree.
public enum WorktreeError: Error, Equatable, Sendable {
    /// The worktree has uncommitted changes (someone edited files in it); only removed when forced.
    case hasChanges(String)
    /// Refused: the path is not inside Sylvra's storage folder.
    case outsideStorage(String)
}

/// Finds and removes Sylvra's worktrees (see specs/architecture.md §9.2): worktrees of merged or closed pull
/// requests and worktrees unused for a week go away; worktrees in use or with uncommitted changes stay.
public struct WorktreeCleaner: Sendable {
    private let git: GitRunner
    public let storageRoot: URL
    public let registry: WorktreeRegistry

    /// Worktrees unused for longer are removed even if their pull request is still open.
    public static let retention: TimeInterval = 7 * 24 * 60 * 60

    public init(git: GitRunner = GitRunner(), storageRoot: URL = CheckoutService.defaultStorageRoot) {
        self.git = git
        self.storageRoot = storageRoot
        registry = WorktreeRegistry(storageRoot: storageRoot)
    }

    /// Why a worktree is removed automatically.
    public enum Reason: Sendable, Equatable {
        case pullRequestClosed
        case unused
    }

    /// The automatic rule: `isOpen` is the pull request's state on GitHub (`nil`: unknown, e.g. offline).
    public nonisolated static func reason(for record: WorktreeRecord, isOpen: Bool?, now: Date = .now) -> Reason? {
        if isOpen == false { return .pullRequestClosed }
        if now.timeIntervalSince(record.lastUsedAt) > retention { return .unused }
        return nil
    }

    /// The registered worktrees plus worktrees found on disk (created before the registry existed); entries
    /// whose folder is gone are dropped.
    public func inventory() async -> [WorktreeRecord] {
        let found = discoverOnDisk()
        await registry.update { records in
            records.removeAll { !FileManager.default.fileExists(atPath: $0.path) }
            for record in found where !records.contains(where: { $0.path == record.path }) {
                records.append(record)
            }
        }
        return await registry.records().sorted { $0.lastUsedAt > $1.lastUsedAt }
    }

    /// Whether files in the worktree were changed (unknown counts as changed, to stay on the safe side).
    public func hasChanges(_ record: WorktreeRecord) async -> Bool {
        guard FileManager.default.fileExists(atPath: record.path) else { return false }
        return (try? await git.isClean(record.url)) != true
    }

    /// Removes a worktree: `git worktree remove` in its clone, then the folder if anything is left.
    /// Without `force`, a worktree with uncommitted changes is kept (`WorktreeError.hasChanges`).
    public func remove(_ record: WorktreeRecord, force: Bool = false) async throws {
        guard record.path.hasPrefix(storageRoot.path + "/") else { throw WorktreeError.outsideStorage(record.path) }
        if !force, await hasChanges(record) { throw WorktreeError.hasChanges(record.path) }
        try await RepositoryLocks.shared.withLock(record.repository) {
            let clone = record.clonePath.map { URL(fileURLWithPath: $0) }
            let hasClone = clone.map { FileManager.default.fileExists(atPath: $0.path) } ?? false
            if let clone, hasClone {
                _ = try? await git.run(["worktree", "remove", "--force", record.path], in: clone)
            }
            if FileManager.default.fileExists(atPath: record.path) {
                try FileManager.default.removeItem(at: record.url)
            }
            if let clone, hasClone { _ = try? await git.run(["worktree", "prune"], in: clone) }
            removeEmptyParents(of: record.url)
        }
        await registry.update { $0.removeAll { $0.path == record.path } }
    }

    /// What a cleanup did.
    public struct Report: Sendable, Equatable {
        public var removed: [WorktreeRecord] = []
        /// Due for removal but kept: files in them were changed.
        public var keptWithChanges: [WorktreeRecord] = []
        public var failed: [WorktreeRecord] = []
        /// Sylvra's own clones (`repos/<owner>/<repo>`) no worktree used any more.
        public var removedClones: [String] = []
    }

    /// Removes the worktrees the automatic rule selects, except those in use (a pull request shown or reviewed,
    /// a terminal tab inside the worktree).
    public func cleanUp(
        isOpen: @Sendable (PullRequestID) async -> Bool?, inUse: Set<PullRequestID>, openDirectories: [URL],
        now: Date = .now
    ) async -> Report {
        var report = Report()
        for record in await inventory() {
            if let id = record.pullRequest, inUse.contains(id) { continue }
            if openDirectories.contains(where: { $0.path == record.path || $0.path.hasPrefix(record.path + "/") }) {
                continue
            }
            let state: Bool? = if let id = record.pullRequest { await isOpen(id) } else { nil }
            guard Self.reason(for: record, isOpen: state, now: now) != nil else { continue }
            do {
                try await remove(record)
                report.removed.append(record)
            } catch WorktreeError.hasChanges {
                report.keptWithChanges.append(record)
            } catch {
                report.failed.append(record)
            }
        }
        report.removedClones = await removeUnusedCacheClones()
        return report
    }

    /// Removes Sylvra's own clones that no worktree belongs to (they are cloned again when needed); local disk
    /// space is precious. Returns the removed `owner/repo`s.
    public func removeUnusedCacheClones() async -> [String] {
        var removed: [String] = []
        for clone in folders(in: storageRoot.appending(path: "repos"), depth: 2) {
            let parts = clone.pathComponents.suffix(2)
            let repository = parts.joined(separator: "/")
            let isRemoved: Bool =
                (try? await RepositoryLocks.shared.withLock(repository) {
                    let canonical = CheckoutService.canonical(clone.path)
                    let used = await inventory().contains {
                        $0.clonePath.map(CheckoutService.canonical) == canonical
                    }
                    guard !used else { return false }
                    try FileManager.default.removeItem(at: clone)
                    removeEmptyParents(of: clone)
                    return true
                }) ?? false
            if isRemoved { removed.append(repository) }
        }
        return removed
    }

    // MARK: Disk

    /// `worktrees/<owner>/<repo>` (IDE) and `agent-worktrees/<owner>/<repo>/pr-<n>` (AI).
    private func discoverOnDisk() -> [WorktreeRecord] {
        let ide = folders(in: storageRoot.appending(path: "worktrees"), depth: 2).map {
            record(at: $0, purpose: .ide, pullRequest: nil)
        }
        let agent = folders(in: storageRoot.appending(path: "agent-worktrees"), depth: 3).map { url in
            let parts = url.pathComponents.suffix(3)
            let number = parts.last.flatMap { $0.hasPrefix("pr-") ? Int($0.dropFirst(3)) : nil }
            let id = number.map {
                PullRequestID(owner: parts[parts.startIndex], repository: parts[parts.startIndex + 1], number: $0)
            }
            return record(at: url, purpose: .agent, pullRequest: id)
        }
        return (ide + agent).filter { FileManager.default.fileExists(atPath: $0.path + "/.git") }
    }

    private func folders(in root: URL, depth: Int) -> [URL] {
        guard depth > 0 else { return [root] }
        let children =
            (try? FileManager.default.contentsOfDirectory(
                at: root, includingPropertiesForKeys: [.isDirectoryKey], options: .skipsHiddenFiles)) ?? []
        // Built from `root`, not the listed URLs: those may resolve symlinks (`/var` → `/private/var`) and then
        // no longer match the registered paths.
        return children.filter { (try? $0.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true }
            .flatMap { folders(in: root.appending(path: $0.lastPathComponent), depth: depth - 1) }
    }

    private func record(at url: URL, purpose: CheckoutService.Purpose, pullRequest: PullRequestID?) -> WorktreeRecord {
        let modified =
            (try? url.resourceValues(forKeys: [.contentModificationDateKey]).contentModificationDate) ?? .now
        return WorktreeRecord(
            path: url.path, purpose: purpose, pullRequest: pullRequest, clonePath: Self.clone(ofWorktree: url),
            createdAt: modified, lastUsedAt: modified)
    }

    /// The clone a worktree belongs to, from its `.git` file (`gitdir: <clone>/.git/worktrees/<name>`).
    nonisolated static func clone(ofWorktree url: URL) -> String? {
        guard let text = try? String(contentsOf: url.appending(path: ".git"), encoding: .utf8),
            let range = text.range(of: "gitdir: ")
        else { return nil }
        let gitDir = text[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
        guard let marker = gitDir.range(of: "/.git/worktrees/") else { return nil }
        return String(gitDir[..<marker.lowerBound])
    }

    /// Removes the now empty `<owner>/<repo>` folders above a removed worktree.
    private func removeEmptyParents(of url: URL) {
        var folder = url.deletingLastPathComponent()
        let roots = ["worktrees", "agent-worktrees", "repos"].map { storageRoot.appending(path: $0).path }
        while folder.path.hasPrefix(storageRoot.path + "/"), !roots.contains(folder.path),
            (try? FileManager.default.contentsOfDirectory(atPath: folder.path))?.isEmpty == true
        {
            try? FileManager.default.removeItem(at: folder)
            folder = folder.deletingLastPathComponent()
        }
    }
}
