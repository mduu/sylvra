import Foundation
import Platform
import SylvraCore
import Testing

@testable import FeatureOpenInIDE

struct GitHubRemoteTests {
    @Test(arguments: [
        "git@github.com:mduu/sylvra.git", "https://github.com/mduu/sylvra", "https://github.com/mduu/sylvra.git",
        "ssh://git@github.com/mduu/sylvra.git",
    ])
    func parsesRemote(url: String) throws {
        let parsed = try #require(GitHubRemote.ownerAndName(from: url))
        #expect(parsed.owner == "mduu" && parsed.name == "sylvra")
    }

    @Test func rejectsOtherHosts() {
        #expect(GitHubRemote.ownerAndName(from: "git@gitlab.com:a/b.git") == nil)
    }
}

struct IDETests {
    let project = URL(fileURLWithPath: "/p")
    let file = URL(fileURLWithPath: "/p/A.swift")

    @Test func launcherArguments() {
        #expect(
            IDE.rider.launcherArguments(project: project, file: file, line: 4) == ["/p", "--line", "4", "/p/A.swift"])
        #expect(
            IDE.vsCode.launcherArguments(project: project, file: file, line: 4) == ["/p", "--goto", "/p/A.swift:4"])
        #expect(IDE.xcode.launcherArguments(project: project, file: file, line: nil) == ["/p/A.swift"])
        #expect(IDE.rider.launcherArguments(project: project, file: nil, line: nil) == ["/p"])
    }

    @Test func detectsProjectFiles() throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "sylvra-detect-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        defer { try? FileManager.default.removeItem(at: directory) }
        FileManager.default.createFile(atPath: directory.appending(path: "App.sln").path, contents: nil)
        try FileManager.default.createDirectory(
            at: directory.appending(path: "App.xcodeproj"), withIntermediateDirectories: true)

        #expect(ProjectDetector.project(in: directory, for: .rider).lastPathComponent == "App.sln")
        #expect(ProjectDetector.project(in: directory, for: .xcode).lastPathComponent == "App.xcodeproj")
        #expect(ProjectDetector.project(in: directory, for: .vsCode) == directory)
    }
}

/// Uses real git with a local "origin" that has a `pull/7/head` ref.
struct CheckoutServiceTests {
    let git = GitRunner()

    // swiftlint:disable:next large_tuple
    private func makeFixture() async throws -> (root: URL, clone: URL, service: CheckoutService) {
        let root = FileManager.default.temporaryDirectory.appending(path: "sylvra-checkout-\(UUID().uuidString)")
        let origin = root.appending(path: "origin")
        let clone = root.appending(path: "Dev/billing")
        try FileManager.default.createDirectory(at: origin, withIntermediateDirectories: true)
        try await git.run(["init", "--quiet", "-b", "main"], in: origin)
        try await git.run(
            ["-c", "user.name=T", "-c", "user.email=t@e", "commit", "--quiet", "--allow-empty", "-m", "base"],
            in: origin)
        try await git.run(
            ["-c", "user.name=T", "-c", "user.email=t@e", "commit", "--quiet", "--allow-empty", "-m", "pr"], in: origin)
        try await git.run(["update-ref", "refs/pull/7/head", "HEAD"], in: origin)
        try await git.run(["reset", "--quiet", "--hard", "HEAD~1"], in: origin)
        try await git.run(["clone", "--quiet", origin.path, clone.path])
        // Make the clone look like a GitHub clone for the locator, but keep fetching from the local origin.
        try await git.run(["remote", "set-url", "origin", "git@github.com:acme/billing.git"], in: clone)
        try await git.run(["config", "url.\(origin.path).insteadOf", "git@github.com:acme/billing.git"], in: clone)
        let locator = RepositoryLocator(git: git, roots: [root.appending(path: "Dev")])
        let service = CheckoutService(git: git, locator: locator, storageRoot: root.appending(path: "Support"))
        return (root, clone, service)
    }

    let id = PullRequestID(owner: "acme", repository: "billing", number: 7)

    @Test func checksOutWorktreeWithoutTouchingClone() async throws {
        let (root, clone, service) = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }

        let worktree = try await service.prepareWorktree(for: id)
        #expect(try await git.run(["log", "-1", "--format=%s"], in: worktree) == "pr")
        #expect(try await git.currentBranch(clone) == "main")
        // Second call re-uses the stable path.
        #expect(try await service.prepareWorktree(for: id) == worktree)
    }

    @Test func mainCloneRequiresConfirmationWhenDirty() async throws {
        let (root, clone, service) = try await makeFixture()
        defer { try? FileManager.default.removeItem(at: root) }
        FileManager.default.createFile(atPath: clone.appending(path: "wip.txt").path, contents: Data("x".utf8))

        await #expect(throws: CheckoutError.self) {
            _ = try await service.prepareMainClone(for: id, stashChanges: false)
        }
        let result = try await service.prepareMainClone(for: id, stashChanges: true)
        #expect(result.previousBranch == "main")
        #expect(try await git.currentBranch(clone) == "review/pr-7")
        #expect(try await git.run(["stash", "list"], in: clone).contains("Sylvra: before reviewing"))
    }
}

@MainActor
struct OpenInIDEModelTests {
    struct DirtyCheckout: CheckoutPreparing {
        func prepareWorktree(for id: PullRequestID) async throws -> URL { URL(fileURLWithPath: "/tmp/w") }
        func prepareMainClone(for id: PullRequestID, stashChanges: Bool) async throws -> (
            clone: URL, previousBranch: String?
        ) {
            if !stashChanges { throw CheckoutError.dirtyWorkingTree(URL(fileURLWithPath: "/tmp/c")) }
            return (URL(fileURLWithPath: "/tmp/c"), "main")
        }
    }

    private func defaults() -> UserDefaults {
        let name = "sylvra-tests-\(UUID().uuidString)"
        return UserDefaults(suiteName: name)!
    }

    let id = PullRequestID(owner: "acme", repository: "billing", number: 7)

    @Test func remembersIDEPerRepository() async {
        let model = OpenInIDEModel(checkout: DemoCheckout(), opener: DemoIDEOpener(), defaults: defaults())
        #expect(model.preferredIDE(for: id) == .rider)
        await model.open(id, in: .xcode)
        #expect(model.preferredIDE(for: id) == .xcode)
        #expect(model.status == .done("Opened in Xcode"))
    }

    @Test func asksBeforeStashing() async {
        let model = OpenInIDEModel(checkout: DirtyCheckout(), opener: DemoIDEOpener(), defaults: defaults())
        model.setCheckoutTarget(.mainClone, for: id)
        await model.open(id)
        #expect(model.stashConfirmation?.pullRequest == id)
        await model.confirmStash()
        #expect(model.stashConfirmation == nil)
        #expect(
            model.status == .done("Opened in Rider — your changes are in a stash named “Sylvra: before reviewing …”"))
    }
}
