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
                "--hint", "thread safety", "--hint=the migration",
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
        #expect(options.hints == ["thread safety", "the migration"])
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
        let runner = LocalReviewRunner(provider: DemoAgentProvider(delay: .zero), heartbeat: .seconds(60)) {
            ReviewSettings(models: ["opus", "fable"], effort: "high", maxParallelAgents: 1)
        }
        var lines: [String] = []
        let report = try await runner.run(LocalReviewOptions(directory: repository.root)) { lines.append($0) }
        #expect(report.fileCount == 2)
        #expect(report.settings.models == ["opus", "fable"])
        #expect(report.result != nil)
        #expect(report.failures.isEmpty)
        // A line when each model's agent finishes (counted), then the step that combines their findings, then
        // the closing line.
        let finished = lines.filter { $0.contains("] ✓ ") }
        #expect(finished.contains { $0.hasPrefix("[1/2 · ") && $0.localizedCaseInsensitiveContains("opus") })
        #expect(finished.contains { $0.hasPrefix("[2/2 · ") && $0.localizedCaseInsensitiveContains("fable") })
        #expect(finished.last?.contains("Combining") == true)
        #expect(lines.last?.hasPrefix("Done in 0:0") == true)

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

/// Progress lines a person or a coding agent can follow.
@MainActor
struct LocalReviewProgressTests {
    final class Clock {
        var now = Date(timeIntervalSince1970: 0)
    }

    @Test func countsAgentsAndTimeButNotTheCombiningStep() {
        let clock = Clock()
        var lines: [String] = []
        let progress = LocalReviewProgress(report: { lines.append($0) }, now: { clock.now })
        progress.update(.init(id: "0#opus", title: "Core · Opus", state: .queued))
        progress.update(.init(id: "0#fable", title: "Core · Fable", state: .queued))
        progress.update(.init(id: "0#opus", title: "Core · Opus", state: .running))
        progress.update(.init(id: "0#fable", title: "Core · Fable", state: .running))
        clock.now += 31
        progress.heartbeat()
        clock.now += 41
        progress.update(.init(id: "0#opus", title: "Core · Opus", state: .done))
        progress.update(.init(id: "0#fable", title: "Core · Fable", state: .failed("timed out")))
        progress.update(.init(id: "consolidate", title: "Combining the models' findings", state: .running))
        progress.heartbeat()
        #expect(
            lines == [
                "[0/2 · 0:00] ▸ Core · Opus",
                "[0/2 · 0:00] ▸ Core · Fable",
                "… 0 of 2 agents done, 2 running · 0:31",
                "[1/2 · 1:12] ✓ Core · Opus",
                "[2/2 · 1:12] ✗ Core · Fable: timed out",
                "[2/2 · 1:12] ▸ Combining the models' findings",
            ])
        #expect(progress.failures == ["Core · Fable: timed out"])
        #expect(!progress.allFailed)
    }

    @Test func theClosingLineSumsUpTheFindings() {
        var result = ReviewResult(risk: RiskAssessment(level: .medium))
        result.findings = [
            ReviewFinding(
                path: "a", startLine: 1, endLine: 1, severity: .major, category: "", title: "", rationale: ""),
            ReviewFinding(
                path: "b", startLine: 1, endLine: 1, severity: .minor, category: "", title: "", rationale: ""),
            ReviewFinding(
                path: "c", startLine: 1, endLine: 1, severity: .minor, category: "", title: "", rationale: ""),
        ]
        #expect(LocalReviewProgress.outcome(result) == "3 findings (1 major, 2 minor), merge risk medium")
        #expect(LocalReviewProgress.outcome(ReviewResult()) == "no findings")
        #expect(LocalReviewProgress.duration(161.7) == "2:41")
    }
}
