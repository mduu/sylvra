import Foundation
import Platform
import SylvraCore
import Testing

@testable import FeatureOpenInIDE

struct WorktreeCleanupRuleTests {
    private func record(usedDaysAgo days: Double) -> WorktreeRecord {
        let used = Date.now.addingTimeInterval(-days * 86_400)
        return WorktreeRecord(
            path: "/x/agent-worktrees/acme/billing/pr-7", purpose: .agent,
            pullRequest: PullRequestID(owner: "acme", repository: "billing", number: 7), clonePath: nil,
            createdAt: used, lastUsedAt: used)
    }

    @Test func removesClosedAndLongUnusedOnly() {
        #expect(WorktreeCleaner.reason(for: record(usedDaysAgo: 0), isOpen: false) == .pullRequestClosed)
        #expect(WorktreeCleaner.reason(for: record(usedDaysAgo: 8), isOpen: true) == .unused)
        #expect(WorktreeCleaner.reason(for: record(usedDaysAgo: 8), isOpen: nil) == .unused)
        #expect(WorktreeCleaner.reason(for: record(usedDaysAgo: 1), isOpen: true) == nil)
        #expect(WorktreeCleaner.reason(for: record(usedDaysAgo: 1), isOpen: nil) == nil)
    }

    @Test func repositoryFromThePathLayout() {
        let ide = WorktreeRecord(
            path: "/x/worktrees/acme/billing", purpose: .ide, pullRequest: nil, clonePath: nil, createdAt: .now,
            lastUsedAt: .now)
        #expect(ide.repository == "acme/billing")
        let agent = WorktreeRecord(
            path: "/x/agent-worktrees/acme/billing/pr-7", purpose: .agent, pullRequest: nil, clonePath: nil,
            createdAt: .now, lastUsedAt: .now)
        #expect(agent.repository == "acme/billing")
    }
}

/// Real git with a local "origin" that has a `pull/7/head` ref (like `CheckoutServiceTests`).
struct WorktreeCleanerTests {
    let git = GitRunner()
    let id = PullRequestID(owner: "acme", repository: "billing", number: 7)

    private struct Fixture {
        let root: URL
        let clone: URL
        let service: CheckoutService
        let cleaner: WorktreeCleaner
    }

    private func makeFixture() async throws -> Fixture {
        let root = FileManager.default.temporaryDirectory.appending(path: "sylvra-cleanup-\(UUID().uuidString)")
        let origin = root.appending(path: "origin")
        let clone = root.appending(path: "Dev/billing")
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
        let commit = ["-c", "user.name=T", "-c", "user.email=t@e", "commit", "--quiet", "--allow-empty", "-m"]
        try await git.run(["init", "--quiet", "-b", "main"], in: origin)
        try await git.run(commit + ["base"], in: origin)
        try await git.run(["update-ref", "refs/pull/7/head", "HEAD"], in: origin)
        try await git.run(["clone", "--quiet", origin.path, clone.path])
        try await git.run(["remote", "set-url", "origin", "git@github.com:acme/billing.git"], in: clone)
        try await git.run(["config", "url.\(origin.path).insteadOf", "git@github.com:acme/billing.git"], in: clone)
        let storage = root.appending(path: "Support")
        let locator = RepositoryLocator(git: git, roots: [root.appending(path: "Dev")])
        return Fixture(
            root: root, clone: clone, service: CheckoutService(git: git, locator: locator, storageRoot: storage),
            cleaner: WorktreeCleaner(git: git, storageRoot: storage))
    }

    @Test func recordsAndRemovesWorktreesOfClosedPullRequests() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let worktree = try await fixture.service.prepareWorktree(for: id, purpose: .agent)

        let listed = await fixture.cleaner.inventory()
        #expect(listed.map(\.path) == [worktree.path])
        #expect(listed.first?.pullRequest == id)

        // Open and in use: kept.
        var report = await fixture.cleaner.cleanUp(isOpen: { _ in false }, inUse: [id], openDirectories: [])
        #expect(report.removed.isEmpty)
        report = await fixture.cleaner.cleanUp(isOpen: { _ in true }, inUse: [], openDirectories: [])
        #expect(report.removed.isEmpty)

        report = await fixture.cleaner.cleanUp(isOpen: { _ in false }, inUse: [], openDirectories: [])
        #expect(report.removed.map(\.path) == [worktree.path])
        #expect(!FileManager.default.fileExists(atPath: worktree.path))
        #expect(await fixture.cleaner.inventory().isEmpty)
        let worktrees = try await git.run(["worktree", "list"], in: fixture.clone)
        #expect(!worktrees.contains("agent-worktrees"))
    }

    @Test func keepsWorktreesWithChangedFilesAndTerminalTabs() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let worktree = try await fixture.service.prepareWorktree(for: id, purpose: .ide)

        var report = await fixture.cleaner.cleanUp(
            isOpen: { _ in false }, inUse: [], openDirectories: [worktree.appending(path: "Sources")])
        #expect(report.removed.isEmpty)

        try "edited".write(to: worktree.appending(path: "notes.txt"), atomically: true, encoding: .utf8)
        report = await fixture.cleaner.cleanUp(isOpen: { _ in false }, inUse: [], openDirectories: [])
        #expect(report.keptWithChanges.map(\.path) == [worktree.path])
        #expect(FileManager.default.fileExists(atPath: worktree.path))

        let record = try #require(await fixture.cleaner.inventory().first)
        try await fixture.cleaner.remove(record, force: true)
        #expect(!FileManager.default.fileExists(atPath: worktree.path))
    }

    /// Worktrees from before the registry are found on disk and can be cleaned up as well.
    @Test func adoptsWorktreesFoundOnDisk() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let worktree = try await fixture.service.prepareWorktree(for: id, purpose: .agent)
        try FileManager.default.removeItem(at: fixture.cleaner.registry.file)

        let found = try #require(await fixture.cleaner.inventory().first)
        #expect(found.path == worktree.path)
        #expect(found.pullRequest == id)
        #expect(found.clonePath != nil)
    }

    /// A worktree made in Sylvra's own clone moves to the user's clone once there is one; the own clone is
    /// then unused and removed (disk space).
    @Test func movesWorktreesToTheUsersCloneAndRemovesUnusedOwnClones() async throws {
        let fixture = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: fixture.root) }
        let storage = fixture.cleaner.storageRoot
        let cache = storage.appending(path: "repos/acme/billing")
        let worktree = fixture.service.worktreePath(for: id, purpose: .ide)
        try await git.run(["clone", "--quiet", fixture.root.appending(path: "origin").path, cache.path])
        try FileManager.default.createDirectory(
            at: worktree.deletingLastPathComponent(), withIntermediateDirectories: true)
        try await git.run(["worktree", "add", "--quiet", "--detach", worktree.path, "HEAD"], in: cache)

        _ = try await fixture.service.prepareWorktree(for: id, purpose: .ide)
        let owner = try #require(WorktreeCleaner.clone(ofWorktree: worktree))
        #expect(CheckoutService.canonical(owner) == CheckoutService.canonical(fixture.clone.path))

        let report = await fixture.cleaner.cleanUp(isOpen: { _ in true }, inUse: [], openDirectories: [])
        #expect(report.removedClones == ["acme/billing"])
        #expect(!FileManager.default.fileExists(atPath: cache.path))
        #expect(!FileManager.default.fileExists(atPath: storage.appending(path: "repos/acme").path))
        #expect(FileManager.default.fileExists(atPath: worktree.path))
    }

    @Test func refusesPathsOutsideTheStorageFolder() async throws {
        let cleaner = WorktreeCleaner(storageRoot: URL(fileURLWithPath: "/tmp/sylvra-none"))
        let record = WorktreeRecord(
            path: "/Users/someone/Dev/billing", purpose: .ide, pullRequest: nil, clonePath: nil, createdAt: .now,
            lastUsedAt: .now)
        await #expect(throws: WorktreeError.outsideStorage(record.path)) {
            try await cleaner.remove(record, force: true)
        }
    }
}
