import FeatureAIReview
import FeatureDiff
import Foundation
import Platform

/// Runs Sylvra's AI review on local changes, with the same engine as the app: shards, several models in parallel,
/// merged and consolidated findings, patterns, risk.
public struct LocalReviewRunner: Sendable {
    /// Where Sylvra keeps its settings (the app's bundle identifier).
    public static let appDefaultsDomain = "com.marcduerst.sylvra"

    private let engine: ReviewEngine
    private let defaults: @Sendable () -> ReviewSettings
    private let runner: any ProcessRunning
    private let heartbeat: Duration

    /// - Parameters:
    ///   - defaults: Sylvra's AI review settings (the app's, unless a test passes others).
    ///   - heartbeat: how often a progress line says the agents are still running.
    public init(
        provider: any AgentProvider = ClaudeCodeProvider(), runner: any ProcessRunning = SystemProcessRunner(),
        heartbeat: Duration = .seconds(30),
        defaults: @escaping @Sendable () -> ReviewSettings = { LocalReviewRunner.appSettings() }
    ) {
        engine = ReviewEngine(provider: provider)
        self.defaults = defaults
        self.runner = runner
        self.heartbeat = heartbeat
    }

    /// The AI review settings saved by the Sylvra app (its defaults when it never saved any).
    public static func appSettings() -> ReviewSettings {
        UserDefaults(suiteName: appDefaultsDomain)?.data(forKey: AIReviewModel.defaultSettingsKey)
            .flatMap { try? JSONDecoder().decode(ReviewSettings.self, from: $0) } ?? ReviewSettings()
    }

    public enum RunError: Error, LocalizedError {
        case allAgentsFailed([String])

        public var errorDescription: String? {
            switch self {
            case .allAgentsFailed(let messages):
                "The review failed: " + (messages.first ?? "no agent finished") + ". Is Claude Code installed and "
                    + "signed in (`claude --version`)?"
            }
        }
    }

    /// Reviews the changes; `report` receives progress lines (for standard error). On the main actor, where
    /// the engine reports its progress.
    @MainActor
    public func run(
        _ options: LocalReviewOptions, report: @escaping @MainActor @Sendable (String) -> Void
    ) async throws -> LocalReviewReport {
        await report("Collecting the changes…")
        let changes = try await LocalChanges.load(
            in: options.directory, base: options.base, committedOnly: options.committedOnly, runner: runner)
        let files = ReviewableFiles.make(from: UnifiedDiffParser.parse(changes.diff))
        let settings = options.settings(from: defaults())
        guard !files.isEmpty else {
            return LocalReviewReport(changes: changes, settings: settings, fileCount: 0, result: nil, failures: [])
        }
        await report(
            "Reviewing \(files.count) file(s) against \(changes.base) with "
                + "\(settings.models.joined(separator: " + ")) (effort \(settings.effort))"
                + (options.hints.isEmpty ? "" : ", \(options.hints.count) hint(s)") + "…")
        let root = changes.root
        let context = await Task.detached { RepoContextDiscovery().documents(in: root) }.value
        let input = ReviewEngine.Input(
            files: files, title: options.title ?? Self.title(for: changes),
            body: options.description ?? Self.body(for: changes), context: context, settings: settings,
            workingDirectory: changes.root, hints: options.hints)
        let progress = LocalReviewProgress(report: report)
        let interval = heartbeat
        let beat = Task { @MainActor in
            while !Task.isCancelled {
                try? await Task.sleep(for: interval)
                guard !Task.isCancelled else { return }
                progress.heartbeat()
            }
        }
        var result = await engine.run(input) { update in progress.update(update) }
        beat.cancel()
        result.reviewedAt = .now
        let failures = progress.failures
        if progress.allFailed { throw RunError.allAgentsFailed(failures) }
        progress.finish(result)
        return LocalReviewReport(
            changes: changes, settings: settings, fileCount: files.count, result: result, failures: failures)
    }

    static func title(for changes: LocalChanges) -> String {
        changes.branch.map { "Local changes on \($0)" } ?? "Local changes"
    }

    /// The commit messages tell the reviewers what the change is meant to do.
    static func body(for changes: LocalChanges) -> String {
        var parts: [String] = []
        if !changes.commitMessages.isEmpty {
            parts.append("Commits:\n" + changes.commitMessages.map { "- \($0)" }.joined(separator: "\n"))
        }
        if changes.includesUncommitted {
            parts.append("Includes uncommitted changes and new files not yet committed (work in progress).")
        }
        return parts.joined(separator: "\n\n")
    }
}

/// What a local review found, and on what.
public struct LocalReviewReport: Sendable {
    public let changes: LocalChanges
    public let settings: ReviewSettings
    public let fileCount: Int
    /// `nil` when there was nothing to review.
    public let result: ReviewResult?
    /// Agents that failed (the others' findings are still merged).
    public let failures: [String]
}
