import FeatureAIReview
import Foundation
import Platform
import Testing

@testable import LocalReview

struct LocalReviewCommandTests {
    let here = URL(fileURLWithPath: "/work/repo", isDirectory: true)

    @Test func parsesAReviewWithOverrides() throws {
        let command = try LocalReviewCommand.parse(
            [
                "review", "--base", "origin/develop", "--models=Opus, fable", "--effort", "xhigh", "--agents", "4",
                "--language", "German", "--json", "-o", "out/review.json", "--committed", "-q",
            ], currentDirectory: here)
        guard case .review(let options) = command else {
            Issue.record("expected a review")
            return
        }
        #expect(options.base == "origin/develop")
        #expect(options.models == ["opus", "fable"])
        #expect(options.effort == "xhigh")
        #expect(options.agents == 4)
        #expect(options.language == "German")
        #expect(options.format == .json)
        #expect(options.output?.path == "/work/repo/out/review.json")
        #expect(options.committedOnly)
        #expect(options.isQuiet)
    }

    @Test func sylvrasSettingsAreTheDefaults() throws {
        let saved = ReviewSettings(
            models: ["opus", "fable"], effort: "high", maxParallelAgents: 3, agentLanguage: "German")
        guard case .review(let plain) = try LocalReviewCommand.parse(["review"], currentDirectory: here),
            case .review(let overridden) = try LocalReviewCommand.parse(
                ["review", "--models", "sonnet", "--effort", "low"], currentDirectory: here)
        else {
            Issue.record("expected reviews")
            return
        }
        #expect(plain.settings(from: saved) == saved)
        let settings = overridden.settings(from: saved)
        #expect(settings.models == ["sonnet"])
        #expect(settings.effort == "low")
        #expect(settings.maxParallelAgents == 3)
        #expect(settings.agentLanguage == "German")
    }

    @Test func refusesWhatItDoesntKnow() throws {
        #expect(throws: LocalReviewCommand.ParseError.unknownCommand("push")) {
            try LocalReviewCommand.parse(["push"], currentDirectory: here)
        }
        #expect(throws: LocalReviewCommand.ParseError.unknownOption("--fix")) {
            try LocalReviewCommand.parse(["review", "--fix"], currentDirectory: here)
        }
        #expect(throws: LocalReviewCommand.ParseError.missingValue("--base")) {
            try LocalReviewCommand.parse(["review", "--base"], currentDirectory: here)
        }
        #expect(throws: (any Error).self) {
            try LocalReviewCommand.parse(["review", "--effort", "extreme"], currentDirectory: here)
        }
        #expect(throws: (any Error).self) {
            try LocalReviewCommand.parse(["review", "--agents", "0"], currentDirectory: here)
        }
        #expect(try LocalReviewCommand.parse([], currentDirectory: here) == .help)
    }
}

/// A throwaway repository: `main` with one commit, a branch with a commit, an uncommitted change and a new file.
struct ScratchRepository {
    let root: URL
    let git = Git(runner: SystemProcessRunner())

    static func make() async throws -> ScratchRepository {
        let root = FileManager.default.temporaryDirectory.appending(path: "LocalReviewTests-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: root, withIntermediateDirectories: true)
        let repository = ScratchRepository(root: root)
        try await repository.run(["init", "-q", "-b", "main"])
        try repository.write("price.py", "def total(items):\n    return sum(items)\n")
        try await repository.commit("Add total")
        try await repository.run(["checkout", "-q", "-b", "feature/discount"])
        try repository.write("price.py", "def total(items, discount=0):\n    return sum(items) * (1 - discount)\n")
        try await repository.commit("Add a discount")
        try repository.write("price.py", "def total(items, discount=0):\n    return sum(items) - discount\n")
        try repository.write("coupon.py", "def apply(code):\n    return 10\n")
        return repository
    }

    func write(_ path: String, _ text: String) throws {
        try Data(text.utf8).write(to: root.appending(path: path))
    }

    func commit(_ message: String) async throws {
        try await run(["add", "."])
        try await run(["-c", "user.email=test@example.com", "-c", "user.name=Test", "commit", "-q", "-m", message])
    }

    func run(_ arguments: [String]) async throws {
        _ = try await git.output(arguments, in: root)
    }
}

struct LocalChangesTests {
    @Test func includesCommitsUncommittedAndNewFiles() async throws {
        let repository = try await ScratchRepository.make()
        let changes = try await LocalChanges.load(in: repository.root, base: nil, committedOnly: false)
        #expect(changes.base == "main")
        #expect(changes.branch == "feature/discount")
        #expect(changes.commitMessages == ["Add a discount"])
        #expect(changes.diff.contains("+    return sum(items) - discount"))
        #expect(changes.diff.contains("b/coupon.py"))
        #expect(changes.includesUncommitted)
    }

    @Test func committedOnlyLeavesWorkInProgressOut() async throws {
        let repository = try await ScratchRepository.make()
        let changes = try await LocalChanges.load(in: repository.root, base: "main", committedOnly: true)
        #expect(changes.diff.contains("+    return sum(items) * (1 - discount)"))
        #expect(!changes.diff.contains("coupon.py"))
        #expect(!changes.diff.contains("- discount\n"))
    }

    @Test func explainsAMissingBase() async throws {
        let repository = try await ScratchRepository.make()
        await #expect(throws: LocalChanges.LoadError.baseNotFound("develop")) {
            try await LocalChanges.load(in: repository.root, base: "develop", committedOnly: false)
        }
        let outside = FileManager.default.temporaryDirectory.appending(path: "NoRepo-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: outside, withIntermediateDirectories: true)
        await #expect(throws: LocalChanges.LoadError.notARepository(outside.path)) {
            try await LocalChanges.load(in: outside, base: nil, committedOnly: false)
        }
    }
}

@MainActor
struct LocalReviewRunnerTests {
    @Test func reviewsTheBranchWithEveryModelAndRendersTheResult() async throws {
        let repository = try await ScratchRepository.make()
        let runner = LocalReviewRunner(provider: DemoAgentProvider(delay: .zero)) {
            ReviewSettings(models: ["opus", "fable"], effort: "high", maxParallelAgents: 1)
        }
        var lines: [String] = []
        let report = try await runner.run(LocalReviewOptions(directory: repository.root)) { lines.append($0) }
        #expect(report.fileCount == 2)
        #expect(report.settings.models == ["opus", "fable"])
        #expect(report.result != nil)
        #expect(report.failures.isEmpty)
        // A line when each model's agent finishes, then the step that combines their findings.
        let finished = lines.filter { $0.hasPrefix("  ✓") }
        #expect(finished.contains { $0.localizedCaseInsensitiveContains("opus") })
        #expect(finished.contains { $0.localizedCaseInsensitiveContains("fable") })
        #expect(finished.last?.contains("Combining") == true)

        let markdown = LocalReviewOutput.markdown(report)
        #expect(markdown.hasPrefix("# Sylvra AI review: feature/discount against main"))
        #expect(markdown.contains("with opus + fable, effort high"))
        let json = try LocalReviewOutput.json(report)
        #expect(json.contains("\"includesUncommitted\" : true"))
        #expect(json.contains("\"models\" : ["))
    }

    @Test func nothingToReviewIsNoError() async throws {
        let repository = try await ScratchRepository.make()
        try await repository.run(["checkout", "-q", "--", "price.py"])
        try FileManager.default.removeItem(at: repository.root.appending(path: "coupon.py"))
        try await repository.run(["checkout", "-q", "main"])
        let runner = LocalReviewRunner(provider: DemoAgentProvider(delay: .zero)) { ReviewSettings() }
        let report = try await runner.run(LocalReviewOptions(directory: repository.root)) { _ in }
        #expect(report.result == nil)
        #expect(LocalReviewOutput.markdown(report).contains("No changes to review against main."))
    }
}

struct AgentEnvironmentTests {
    @Test func agentsDontJoinTheCallersClaudeSession() {
        #expect(ExecutableLocatorProbe.isCallerSession("CLAUDECODE"))
        #expect(ExecutableLocatorProbe.isCallerSession("CLAUDE_CODE_SESSION_ID"))
        #expect(!ExecutableLocatorProbe.isCallerSession("CLAUDE_CONFIG_DIR"))
        #expect(!ExecutableLocatorProbe.isCallerSession("ANTHROPIC_API_KEY"))
    }
}

/// `ExecutableLocator.isCallerSessionVariable` is internal to Platform; the environment shows its effect.
enum ExecutableLocatorProbe {
    static func isCallerSession(_ name: String) -> Bool {
        setenv(name, "1", 1)
        defer { unsetenv(name) }
        return ExecutableLocator.environment[name] == nil
    }
}
