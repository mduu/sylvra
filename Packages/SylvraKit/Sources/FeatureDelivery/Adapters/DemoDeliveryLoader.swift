import Foundation
import SylvraCore

/// A delivery half way to production (demo mode, previews, tests): a build that splits into three test jobs
/// and joins again, dev deployed, test deploying, prod waiting for approval.
public struct DemoDeliveryLoader: DeliveryLoading {
    public init() {}

    public func loadDelivery(for id: PullRequestID) async throws -> Delivery? { Self.delivery(for: id) }
    public func approve(_ approval: DeliveryStage.Approval) async throws {}

    public func loadLog(jobID: Int, in id: PullRequestID) async throws -> String {
        try await Task.sleep(for: .milliseconds(300))
        return Self.log
    }

    public static func delivery(for id: PullRequestID, now: Date = .now) -> Delivery {
        func job(
            _ name: String, _ state: StageState, from start: TimeInterval, for length: TimeInterval?,
            needs: [String] = [], steps: [JobStep] = []
        ) -> DeliveryJob {
            DeliveryJob(
                id: name, name: name, state: state, startedAt: now.addingTimeInterval(start),
                finishedAt: length.map { now.addingTimeInterval(start + $0) },
                url: URL(string: "https://github.com/acme/billing/actions"), jobID: name.count, needs: needs,
                steps: steps)
        }
        let deploySteps = [
            JobStep(number: 1, name: "Set up job", state: .succeeded),
            JobStep(number: 2, name: "Checkout", state: .succeeded),
            JobStep(number: 3, name: "Log in to the registry", state: .succeeded),
            JobStep(number: 4, name: "Run migrations", state: .running),
            JobStep(number: 5, name: "Roll out", state: .waiting),
            JobStep(number: 6, name: "Wait for pods", state: .waiting),
            JobStep(number: 7, name: "Post deploy", state: .waiting),
        ]
        let tests = ["Unit tests", "Integration tests", "Lint"]
        let runs = [
            StagePlanner.Run(
                id: "run1", name: "CI/CD", event: "push", url: URL(string: "https://github.com/acme/billing/actions"),
                createdAt: now.addingTimeInterval(-1_500),
                jobs: [
                    .init(job: job("Compile", .succeeded, from: -1_500, for: 110)),
                    .init(job: job("Unit tests", .succeeded, from: -1_380, for: 130, needs: ["Compile"])),
                    .init(job: job("Integration tests", .succeeded, from: -1_380, for: 150, needs: ["Compile"])),
                    .init(job: job("Lint", .succeeded, from: -1_380, for: 40, needs: ["Compile"])),
                    .init(job: job("Deploy dev", .succeeded, from: -1_220, for: 80, needs: tests), environment: "dev"),
                    .init(
                        job: job("Smoke tests dev", .succeeded, from: -1_130, for: 60, needs: ["Deploy dev"]),
                        environment: "dev"),
                    .init(
                        job: job(
                            "Deploy test", .running, from: -190, for: nil, needs: ["Smoke tests dev"],
                            steps: deploySteps),
                        environment: "test"),
                    .init(
                        job: job("Smoke tests test", .waiting, from: 0, for: nil, needs: ["Deploy test"]),
                        environment: "test"),
                ],
                pending: [.init(environment: "prod", environmentID: "env-prod", viewerCanApprove: true)])
        ]
        return Delivery(
            pullRequest: id, title: "Fix VAT rounding", mergeCommitSHA: "4f9c2e1a7b",
            mergedAt: now.addingTimeInterval(-1_560), stages: StagePlanner.stages(runs: runs))
    }

    static let log = """
        2026-11-26T14:30:41.1Z ##[group]Run actions/checkout@v4
        2026-11-26T14:30:41.2Z Syncing repository: acme/billing
        2026-11-26T14:30:43.0Z ##[endgroup]
        2026-11-26T14:30:43.4Z ##[group]Run ./deploy/migrate.sh dev
        2026-11-26T14:30:44.9Z Applying migration 0142_invoice_vat_totals … done (1.2 s)
        2026-11-26T14:30:45.1Z ##[endgroup]
        2026-11-26T14:30:45.3Z ##[group]Run kubectl rollout status deploy/billing-api -n dev
        2026-11-26T14:31:20.6Z Waiting for deployment "billing-api" rollout to finish: 1 of 3 updated replicas are available...
        2026-11-26T14:31:41.8Z Waiting for deployment "billing-api" rollout to finish: 2 of 3 updated replicas are available...
        2026-11-26T14:32:03.9Z deployment "billing-api" successfully rolled out
        2026-11-26T14:32:04.0Z ##[endgroup]
        """
}
