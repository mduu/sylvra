import Foundation
import SylvraCore

/// A delivery half way to production (demo mode, previews, tests).
public struct DemoDeliveryLoader: DeliveryLoading {
    public init() {}

    public func loadDelivery(for id: PullRequestID) async throws -> Delivery? { Self.delivery(for: id) }
    public func approve(_ approval: DeliveryStage.Approval) async throws {}

    public static func delivery(for id: PullRequestID, now: Date = .now) -> Delivery {
        func job(_ name: String, _ state: StageState, from start: TimeInterval, for length: TimeInterval?)
            -> DeliveryJob
        {
            DeliveryJob(
                id: name, name: name, state: state, startedAt: now.addingTimeInterval(start),
                finishedAt: length.map { now.addingTimeInterval(start + $0) },
                url: URL(string: "https://github.com/acme/billing/actions"))
        }
        let runs = [
            StagePlanner.Run(
                id: "run1", name: "Build", event: "push", url: URL(string: "https://github.com/acme/billing/actions"),
                createdAt: now.addingTimeInterval(-1_500),
                jobs: [
                    .init(job: job("Compile", .succeeded, from: -1_500, for: 190)),
                    .init(job: job("Unit tests", .succeeded, from: -1_500, for: 260)),
                    .init(job: job("Deploy dev", .succeeded, from: -1_200, for: 140), environment: "dev"),
                    .init(job: job("Smoke tests dev", .succeeded, from: -1_050, for: 60), environment: "dev"),
                    .init(job: job("Deploy test", .running, from: -420, for: nil), environment: "test"),
                ],
                pending: [.init(environment: "prod", environmentID: "env-prod", viewerCanApprove: true)])
        ]
        return Delivery(
            pullRequest: id, title: "Fix VAT rounding", mergeCommitSHA: "4f9c2e1a7b",
            mergedAt: now.addingTimeInterval(-1_560),
            stages: StagePlanner.stages(runs: runs))
    }
}
