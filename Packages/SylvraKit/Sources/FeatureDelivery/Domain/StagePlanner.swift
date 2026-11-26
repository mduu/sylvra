import Foundation

/// Turns what GitHub reports for a merge commit — workflow runs with their jobs, and deployments — into the
/// stages of a delivery.
///
/// A workflow's jobs that deploy nowhere form one stage named after the workflow (the build); each environment
/// a job deploys to is a stage of its own. Deployments reported by other systems add a stage per environment.
public enum StagePlanner {
    public struct Run: Sendable {
        public var id: String
        public var name: String
        public var event: String
        public var url: URL?
        public var createdAt: Date?
        public var jobs: [Job]
        /// Environments that wait for an approval before their jobs start.
        public var pending: [Pending]
        /// The workflow file: tells which job waits for which (`nil`: unknown, the jobs stand side by side).
        public var workflow: WorkflowFile?

        public init(
            id: String, name: String, event: String, url: URL? = nil, createdAt: Date? = nil, jobs: [Job] = [],
            pending: [Pending] = []
        ) {
            self.id = id
            self.name = name
            self.event = event
            self.url = url
            self.createdAt = createdAt
            self.jobs = jobs
            self.pending = pending
        }
    }

    public struct Job: Sendable {
        public var job: DeliveryJob
        /// The environment the job deploys to.
        public var environment: String?

        public init(job: DeliveryJob, environment: String? = nil) {
            self.job = job
            self.environment = environment
        }
    }

    public struct Pending: Sendable {
        public var environment: String
        public var environmentID: String
        public var viewerCanApprove: Bool

        public init(environment: String, environmentID: String, viewerCanApprove: Bool) {
            self.environment = environment
            self.environmentID = environmentID
            self.viewerCanApprove = viewerCanApprove
        }
    }

    /// A deployment GitHub knows for the commit, whoever created it.
    public struct Deployment: Sendable {
        public var environment: String
        public var state: StageState
        public var createdAt: Date?
        public var finishedAt: Date?
        public var url: URL?

        public init(
            environment: String, state: StageState, createdAt: Date? = nil, finishedAt: Date? = nil, url: URL? = nil
        ) {
            self.environment = environment
            self.state = state
            self.createdAt = createdAt
            self.finishedAt = finishedAt
            self.url = url
        }
    }

    /// What starts a delivery's workflows: the push of the merge commit and what follows from it. Runs for the
    /// pull request itself (its checks) and ones that merely ran on the same commit (schedules, issue
    /// comments) are not part of the delivery.
    static let deliveringEvents: Set<String> = [
        "push", "workflow_run", "workflow_call", "workflow_dispatch", "deployment", "deployment_status", "release",
        "repository_dispatch", "create", "registry_package",
    ]

    public static func stages(runs: [Run], deployments: [Deployment] = []) -> [DeliveryStage] {
        var stages: [DeliveryStage] = []
        let delivering = runs.filter { deliveringEvents.contains($0.event) }
            .sorted { ($0.createdAt ?? .distantFuture) < ($1.createdAt ?? .distantFuture) }
        for var run in delivering {
            run.jobs = linked(run.jobs, by: run.workflow)
            let build = run.jobs.filter { $0.environment == nil }.map(\.job)
            if !build.isEmpty {
                let own = stage(id: "\(run.id)#build", name: run.name, kind: .build, run: run, jobs: build)
                // Several workflows that only build and check (lint, tests, scans) run side by side: one stage.
                if let last = stages.last, last.kind == .build {
                    stages[stages.count - 1] = combined(last, own)
                } else {
                    stages.append(own)
                }
            }
            var environments: [String] = []
            for name in run.jobs.compactMap(\.environment) + run.pending.map(\.environment)
            where !environments.contains(name) {
                environments.append(name)
            }
            for environment in environments {
                let jobs = run.jobs.filter { $0.environment == environment }.map(\.job)
                var stage = stage(
                    id: "\(run.id)#\(environment)", name: environment, kind: .environment, run: run, jobs: jobs)
                if let pending = run.pending.first(where: { $0.environment == environment }), !stage.state.isFinished {
                    stage = DeliveryStage(
                        id: stage.id, name: stage.name, kind: .environment, workflow: run.name, state: .needsApproval,
                        jobs: jobs, startedAt: stage.startedAt, url: run.url,
                        approval: .init(
                            workflowRunID: run.id, environmentID: pending.environmentID,
                            viewerCanApprove: pending.viewerCanApprove))
                }
                stages.append(stage)
            }
        }
        return stages + external(deployments, besides: stages)
    }

    /// Deployments no workflow job stands for (another system reported them): the latest per environment.
    private static func external(_ deployments: [Deployment], besides stages: [DeliveryStage]) -> [DeliveryStage] {
        let known = Set(stages.filter { $0.kind == .environment }.map { $0.name.lowercased() })
        var external: [String: Deployment] = [:]
        for deployment in deployments where !known.contains(deployment.environment.lowercased()) {
            let key = deployment.environment.lowercased()
            if (external[key]?.createdAt ?? .distantPast) <= (deployment.createdAt ?? .distantPast) {
                external[key] = deployment
            }
        }
        return external.values
            .sorted { ($0.createdAt ?? .distantFuture) < ($1.createdAt ?? .distantFuture) }
            .map { deployment in
                DeliveryStage(
                    id: "deployment#\(deployment.environment)", name: deployment.environment, kind: .environment,
                    workflow: nil, state: deployment.state, startedAt: deployment.createdAt,
                    finishedAt: deployment.state.isFinished ? deployment.finishedAt : nil, url: deployment.url)
            }
    }

    /// Fills in each job's `needs` from the workflow file: the jobs (all matrix instances) of the keys it needs.
    static func linked(_ jobs: [Job], by workflow: WorkflowFile?) -> [Job] {
        guard let workflow else { return jobs }
        let keys = jobs.map { workflow.job(forCheckRun: $0.job.name)?.key }
        return jobs.enumerated().map { index, job in
            guard let key = keys[index], let spec = workflow.jobs.first(where: { $0.key == key }) else { return job }
            var linked = job
            linked.job.needs = jobs.indices.filter { other in
                keys[other].map(spec.needs.contains) == true
            }.map { jobs[$0].job.id }
            return linked
        }
    }

    /// Two build stages as one; the jobs say which workflow they belong to.
    private static func combined(_ first: DeliveryStage, _ second: DeliveryStage) -> DeliveryStage {
        func jobs(_ stage: DeliveryStage) -> [DeliveryJob] {
            // A stage combined before has its jobs named already.
            guard let workflow = stage.workflow else { return stage.jobs }
            return stage.jobs.map { job in
                var job = job
                job.name = "\(workflow) · \(job.name)"
                return job
            }
        }
        let all = jobs(first) + jobs(second)
        let state = DeliveryStage.state(of: all.map(\.state))
        return DeliveryStage(
            id: first.id, name: String(localized: "Build & checks"), kind: .build, workflow: nil, state: state,
            jobs: all, startedAt: [first.startedAt, second.startedAt].compactMap { $0 }.min(),
            finishedAt: state.isFinished ? all.compactMap(\.finishedAt).max() : nil, url: first.url)
    }

    private static func stage(id: String, name: String, kind: DeliveryStage.Kind, run: Run, jobs: [DeliveryJob])
        -> DeliveryStage
    {
        let state = DeliveryStage.state(of: jobs.map(\.state))
        let finished = jobs.compactMap(\.finishedAt).max()
        return DeliveryStage(
            id: id, name: name, kind: kind, workflow: run.name, state: state, jobs: jobs,
            startedAt: jobs.compactMap(\.startedAt).min(), finishedAt: state.isFinished ? finished : nil, url: run.url)
    }
}
