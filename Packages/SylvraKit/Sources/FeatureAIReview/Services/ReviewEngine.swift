import Foundation

/// Runs one agent per shard and model with limited concurrency and merges the results.
public struct ReviewEngine: Sendable {
    public struct Progress: Sendable, Equatable {
        public enum State: Sendable, Equatable {
            case queued, running, done, failed(String)
            /// A step that turned out not to be needed (e.g. combining when only one model answered).
            case skipped
        }

        public let id: String
        public let title: String
        public var state: State
        /// Tokens the step used (known once it is done).
        public var tokens: TokenUsage?

        public init(id: String, title: String, state: State, tokens: TokenUsage? = nil) {
            self.id = id
            self.title = title
            self.state = state
            self.tokens = tokens
        }
    }

    /// The step after the agents that combines several models' findings (not an agent itself).
    public static let consolidationID = "consolidate"
    static var consolidationTitle: String { String(localized: "Combining the models' findings") }

    private let provider: any AgentProvider

    public init(provider: any AgentProvider) {
        self.provider = provider
    }

    public var providerName: String { provider.name }

    func providerVersion() async -> String? { await provider.detectVersion() }

    /// One agent run: a shard reviewed by one model.
    public struct Job: Sendable {
        public let id: String
        public let shard: ShardPlanner.Shard
        public let model: String
    }

    /// What to review.
    public struct Input: Sendable {
        public var files: [ReviewableFile]
        public var title: String
        public var body: String
        public var context: [ContextDocument]
        public var history: [String]
        public var settings: ReviewSettings
        public var workingDirectory: URL?
        /// Points the author asks the reviewers to pay particular attention to.
        public var hints: [String]

        public init(
            files: [ReviewableFile], title: String, body: String, context: [ContextDocument] = [],
            history: [String] = [], settings: ReviewSettings, workingDirectory: URL?, hints: [String] = []
        ) {
            self.hints = hints
            self.files = files
            self.title = title
            self.body = body
            self.context = context
            self.history = history
            self.settings = settings
            self.workingDirectory = workingDirectory
        }
    }

    /// Jobs (shard × model) in the order they will run.
    public static func jobs(shards: [ShardPlanner.Shard], models: [String]) -> [Job] {
        shards.enumerated().flatMap { index, shard in
            models.map { model in Job(id: "\(index)#\(model)", shard: shard, model: model) }
        }
    }

    public func run(_ input: Input, progress: @escaping @MainActor @Sendable (Progress) -> Void) async -> ReviewResult {
        let (files, title, body, context) = (input.files, input.title, input.body, input.context)
        let (history, settings, workingDirectory) = (input.history, input.settings, input.workingDirectory)
        let shards = ShardPlanner.plan(files, maxShards: settings.maxParallelAgents, threshold: settings.shardThreshold)
        let models = settings.models.isEmpty ? ["opus"] : settings.models
        let jobs = Self.jobs(shards: shards, models: models)
        for job in jobs {
            await progress(Progress(id: job.id, title: Self.title(job.shard.name, job.model, models), state: .queued))
        }
        // Shown up front, so the reviewer sees what still comes after the agents.
        if models.count > 1 {
            await progress(Progress(id: Self.consolidationID, title: Self.consolidationTitle, state: .queued))
        }

        var outputs: [(AgentReviewOutput, AgentSource)] = []
        await withTaskGroup(of: (AgentReviewOutput, AgentSource)?.self) { group in
            var pending = jobs[...]
            func startNext() {
                guard let job = pending.popFirst() else { return }
                group.addTask {
                    let label = Self.title(job.shard.name, job.model, models)
                    await progress(Progress(id: job.id, title: label, state: .running))
                    var request = ReviewRequest(
                        pullRequestTitle: title, pullRequestBody: body, shard: job.shard, repositoryContext: context,
                        history: history, model: job.model, effort: settings.effort, language: settings.agentLanguage,
                        workingDirectory: workingDirectory)
                    request.otherFiles = Self.otherFiles(files, outside: job.shard)
                    request.hints = input.hints
                    do {
                        let output = try await provider.review(request)
                        await progress(Progress(id: job.id, title: label, state: .done, tokens: output.tokens))
                        return (output, AgentSource(provider: provider.name, model: job.model, effort: settings.effort))
                    } catch {
                        await progress(Progress(id: job.id, title: label, state: .failed(String(describing: error))))
                        return nil
                    }
                }
            }
            for _ in 0..<max(1, settings.maxParallelAgents) { startNext() }
            for await output in group {
                if let output { outputs.append(output) }
                startNext()
            }
        }
        var merged = ReviewMerger.merge(outputs, files: files)
        merged.hints = ReviewMerger.hintAnswers(input.hints, outputs: outputs)
        return await consolidate(merged, outputs: outputs, models: models, settings: settings, progress: progress)
    }

    /// Several models phrase the same problem differently: one more call groups what the merger missed.
    private func consolidate(
        _ merged: ReviewResult, outputs: [(AgentReviewOutput, AgentSource)], models: [String],
        settings: ReviewSettings, progress: @escaping @MainActor @Sendable (Progress) -> Void
    ) async -> ReviewResult {
        let summaries = outputs.map(\.0.summary)
        guard Set(outputs.map(\.1.model)).count > 1,
            FindingConsolidator.isWorthwhile(merged) || FindingConsolidator.distinct(summaries).count > 1
        else {
            if models.count > 1 {
                await progress(Progress(id: Self.consolidationID, title: Self.consolidationTitle, state: .skipped))
            }
            return merged
        }
        let step = Progress(id: Self.consolidationID, title: Self.consolidationTitle, state: .running)
        await progress(step)
        var result = await FindingConsolidator(provider: provider).consolidate(
            merged, summaries: summaries, language: settings.agentLanguage)
        await progress(Progress(id: step.id, title: step.title, state: .done, tokens: result.tokens))
        // The review's total is summed from the steps by whoever runs it.
        result.tokens = nil
        return result
    }

    /// The pull request's files a shard doesn't review, with their size, so it can judge the change as a whole.
    static func otherFiles(_ files: [ReviewableFile], outside shard: ShardPlanner.Shard) -> [String] {
        let reviewed = Set(shard.files.map(\.path))
        return files.filter { !reviewed.contains($0.path) }.map { "\($0.path) (+\($0.changedNewLines.count))" }
    }

    private static func title(_ shard: String, _ model: String, _ models: [String]) -> String {
        models.count > 1 ? "\(shard) · \(model.capitalized)" : shard
    }
}
