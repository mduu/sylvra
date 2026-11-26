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
        var result = StageVerification(
            stageID: stage.id, stageName: stage.name, verdict: .healthy,
            summary: "Deployed to \(stage.name); no new errors, and the rounding error is gone from the logs.",
            intent: "Fixes VAT amounts being rounded per line instead of per invoice.",
            checks: [
                .init(
                    title: "Deployment finished", outcome: .ok, finding: "Version 4f9c2e1 runs on all three pods.",
                    evidence: "Datadog · version tag since 14:32",
                    query: "service:billing-api env:\(stage.name) version:4f9c2e1",
                    excerpt: [
                        "14:32:04 INFO Deployment billing-api 4f9c2e1 rolled out (3/3 pods ready)"
                    ]),
                .init(
                    title: "New errors", outcome: .ok, finding: "Error rate unchanged: 0.21 % before, 0.19 % after.",
                    evidence: "Datadog logs · 30 min before / after",
                    query: "service:billing-api env:\(stage.name) status:error", before: "0.21 %", after: "0.19 %"),
                .init(
                    title: "Effect of the change", outcome: .ok,
                    finding: "\"VAT total mismatch\" appeared 14 times in the hour before, not since.",
                    evidence: "Datadog logs · 60 min before / 20 min after",
                    query: "service:billing-api env:\(stage.name) \"VAT total mismatch\"", before: "14 matches",
                    after: "0 matches",
                    excerpt: [
                        "14:19:07 ERROR InvoiceTotals: VAT total mismatch invoice=INV-88240 lines=118.02 total=118.01",
                        "14:27:31 ERROR InvoiceTotals: VAT total mismatch invoice=INV-88262 lines=9.51 total=9.50",
                        "14:32:04 INFO  Deployment billing-api 4f9c2e1 rolled out (3/3 pods ready)",
                        "14:33:40 INFO  InvoiceTotals: computed invoice=INV-88271 total=63.40 vat=4.76",
                    ]),
            ],
            notChecked: ["The invoice preview in the UI (no trace in logs or metrics)."])
        result.activity = [
            "Read: AGENTS.md",
            "Bash: gh pr diff 812",
            "datadog · search_logs: service:billing-api env:\(stage.name) status:error",
            "datadog · search_logs: service:billing-api env:\(stage.name) \"VAT total mismatch\"",
            "datadog · get_monitors: service:billing-api",
        ]
        return result
    }
}
