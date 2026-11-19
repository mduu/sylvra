import AppKit
import Foundation
import Observation
import Platform
import SylvraCore

/// Sylvra's worktrees: the list for the settings, cleanup in the background every 15 minutes and on demand.
@MainActor
@Observable
public final class WorktreesModel {
    /// A worktree with what the list shows about it.
    public struct Entry: Identifiable, Equatable, Sendable {
        public var id: String { record.id }
        public let record: WorktreeRecord
        public let hasChanges: Bool
        /// In the user's own clone: Git clients (Fork, Tower, IDEs) list it among the clone's worktrees.
        public let isInUserClone: Bool
    }

    /// What the app is using right now; never removed automatically.
    public struct Usage: Sendable {
        public var pullRequests: Set<PullRequestID>
        public var directories: [URL]

        public init(pullRequests: Set<PullRequestID> = [], directories: [URL] = []) {
            self.pullRequests = pullRequests
            self.directories = directories
        }
    }

    public private(set) var entries: [Entry] = []
    public private(set) var isWorking = false
    public private(set) var lastCleanup: Date?
    /// The outcome of the last cleanup or removal, shown under the list.
    public private(set) var message: String?

    public static let interval: Duration = .seconds(15 * 60)

    /// Where the user's clones are looked for; saved per Mac on every change.
    public var repositorySearch: RepositorySearchSettings {
        didSet { repositorySearch.save(to: defaults) }
    }
    private let defaults: UserDefaults

    private let cleaner: WorktreeCleaner
    private let isOpen: @Sendable (PullRequestID) async -> Bool?
    private let usage: @MainActor () -> Usage
    private let logger = SylvraLog.logger("worktrees")

    /// - Parameters:
    ///   - isOpen: the pull request's state on GitHub (`nil` when unknown).
    ///   - usage: pull requests and folders in use, kept even if due for removal.
    public init(
        cleaner: WorktreeCleaner = WorktreeCleaner(),
        isOpen: @escaping @Sendable (PullRequestID) async -> Bool?,
        usage: @escaping @MainActor () -> Usage,
        defaults: UserDefaults = .standard
    ) {
        self.defaults = defaults
        repositorySearch = RepositorySearchSettings.load(from: defaults)
        self.cleaner = cleaner
        self.isOpen = isOpen
        self.usage = usage
    }

    public var storageRoot: URL { cleaner.storageRoot }

    public func addRepositoryFolder(_ url: URL) {
        guard !repositorySearch.folders.contains(url.path) else { return }
        repositorySearch.folders.append(url.path)
    }

    public func removeRepositoryFolder(_ path: String) {
        repositorySearch.folders.removeAll { $0 == path }
    }

    /// Puts back the folders found with typical names (`~/Dev`, `~/dev`, `~/Projects` …).
    public func suggestRepositoryFolders() {
        for url in RepositorySearchSettings.suggestedFolders() { addRepositoryFolder(url) }
    }

    public func refresh() async {
        let cleaner = cleaner
        let root = cleaner.storageRoot
        let records = await cleaner.inventory()
        var result: [Entry] = []
        for record in records {
            result.append(
                Entry(
                    record: record, hasChanges: await cleaner.hasChanges(record),
                    isInUserClone: record.isInUserClone(storageRoot: root)))
        }
        entries = result
    }

    /// Cleans up right away, then every 15 minutes while the app runs.
    public func keepCleaning() async {
        while !Task.isCancelled {
            await cleanUp()
            try? await Task.sleep(for: Self.interval)
        }
    }

    /// Removes worktrees of merged or closed pull requests and worktrees unused for a week.
    public func cleanUp() async {
        guard !isWorking else { return }
        isWorking = true
        defer { isWorking = false }
        let current = usage()
        let report = await cleaner.cleanUp(
            isOpen: isOpen, inUse: current.pullRequests, openDirectories: current.directories)
        lastCleanup = .now
        message = Self.describe(report)
        if !report.removed.isEmpty {
            logger.info("Removed \(report.removed.count, privacy: .public) worktree(s)")
        }
        await refresh()
    }

    /// Removes one worktree; `force` also discards changed files in it.
    public func remove(_ entry: Entry, force: Bool = false) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await cleaner.remove(entry.record, force: force || !entry.hasChanges)
            message = String(localized: "Removed the worktree of \(entry.record.repository).")
        } catch {
            message = String(localized: "Couldn't remove the worktree: \(error.localizedDescription)")
        }
        await refresh()
    }

    /// Opens Sylvra's storage folder (worktrees and cache clones) in the Finder.
    public func showInFinder() {
        try? FileManager.default.createDirectory(at: storageRoot, withIntermediateDirectories: true)
        NSWorkspace.shared.open(storageRoot)
    }

    public func reveal(_ entry: Entry) {
        NSWorkspace.shared.activateFileViewerSelecting([entry.record.url])
    }

    nonisolated static func describe(_ report: WorktreeCleaner.Report) -> String {
        var parts: [String] = []
        parts.append(
            report.removed.isEmpty && report.removedClones.isEmpty
                ? String(localized: "Nothing to clean up.")
                : String(localized: "Removed \(report.removed.count) worktree(s)."))
        if !report.keptWithChanges.isEmpty {
            parts.append(String(localized: "Kept \(report.keptWithChanges.count) with changed files."))
        }
        if !report.failed.isEmpty {
            parts.append(String(localized: "\(report.failed.count) couldn't be removed."))
        }
        if !report.removedClones.isEmpty {
            parts.append(String(localized: "Removed \(report.removedClones.count) unused clone(s)."))
        }
        return parts.joined(separator: " ")
    }
}
