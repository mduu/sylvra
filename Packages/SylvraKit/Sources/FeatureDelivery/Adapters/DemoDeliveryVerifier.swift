import Foundation

/// A canned verification (demo mode, previews).
public struct DemoDeliveryVerifier: DeliveryVerifying {
    private let delay: Duration

    public init(delay: Duration = .seconds(2)) {
        self.delay = delay
    }

    public func verify(_ request: VerificationRequest) async throws -> StageVerification {
        try await Task.sleep(for: delay)
        return Self.verification(for: request.stage)
    }

    public static func verification(for stage: DeliveryStage) -> StageVerification {
        StageVerification(
            stageID: stage.id, stageName: stage.name, verdict: .healthy,
            summary: "Deployed to \(stage.name); no new errors, and the rounding error is gone from the logs.",
            intent: "Fixes VAT amounts being rounded per line instead of per invoice.",
            checks: [
                .init(
                    title: "Deployment finished", outcome: .ok,
                    finding: "Version 4f9c2e1 runs on all three pods.",
                    evidence: "Datadog · service:billing-api env:\(stage.name) · version tag since 14:32"),
                .init(
                    title: "New errors", outcome: .ok, finding: "Error rate unchanged: 0.21 % before, 0.19 % after.",
                    evidence: "Datadog logs · status:error service:billing-api · 30 min before / after"),
                .init(
                    title: "Effect of the change", outcome: .ok,
                    finding: "\"VAT total mismatch\" appeared 14 times in the hour before, not since.",
                    evidence: "Datadog logs · \"VAT total mismatch\" env:\(stage.name) · 60 min before / 20 min after"),
            ],
            notChecked: ["The invoice preview in the UI (no trace in logs or metrics)."])
    }
}
