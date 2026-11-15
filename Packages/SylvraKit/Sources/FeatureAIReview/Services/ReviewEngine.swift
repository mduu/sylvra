import Foundation

/// Runs one agent per shard and model with limited concurrency and merges the results.
public struct ReviewEngine: Sendable {
    public struct Progress: Sendable, Equatable {
        public enum State: Sendable, Equatable {
            case queued, running, done, failed(String)
        }

        public let id: String
        public let title: String
        public var state: State
    }

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
    }

    /// Jobs (shard × model) in the order they will run.
    public static func jobs(shards: [ShardPlanner.Shard], models: [String]) -> [Job] {
        shards.flatMap { shard in
            models.map { model in Job(id: "\(shard.name)#\(model)", shard: shard, model: model) }
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

        var outputs: [(AgentReviewOutput, AgentSource)] = []
        await withTaskGroup(of: (AgentReviewOutput, AgentSource)?.self) { group in
            var pending = jobs[...]
            func startNext() {
                guard let job = pending.popFirst() else { return }
                group.addTask {
                    let label = Self.title(job.shard.name, job.model, models)
                    await progress(Progress(id: job.id, title: label, state: .running))
                    let request = ReviewRequest(
                        pullRequestTitle: title, pullRequestBody: body, shard: job.shard, repositoryContext: context,
                        history: history, model: job.model, effort: settings.effort, language: settings.agentLanguage,
                        workingDirectory: workingDirectory)
                    do {
                        let output = try await provider.review(request)
                        await progress(Progress(id: job.id, title: label, state: .done))
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
        return ReviewMerger.merge(outputs, files: files)
    }

    private static func title(_ shard: String, _ model: String, _ models: [String]) -> String {
        models.count > 1 ? "\(shard) · \(model.capitalized)" : shard
    }
}
