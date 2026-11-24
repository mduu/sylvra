import Foundation
import Testing

@testable import FeatureAIReview

/// While a review runs, the steps still to come are listed too: combining several models' findings.
@MainActor
struct ReviewStepsTests {
    private static let files = [
        ReviewableFile(
            path: "Sources/Billing/InvoiceService.swift", patch: "@@ -1 +1 @@\n+x", changedNewLines: [8, 9, 10],
            visibleNewLines: Set(5...13), isNoise: false)
    ]

    private func run(models: [String]) async -> [[String: ReviewEngine.Progress.State]] {
        var snapshots: [[String: ReviewEngine.Progress.State]] = []
        var current: [String: ReviewEngine.Progress.State] = [:]
        _ = await ReviewEngine(provider: DemoAgentProvider(delay: .zero)).run(
            .init(
                files: Self.files, title: "t", body: "", settings: ReviewSettings(models: models),
                workingDirectory: nil)
        ) { update in
            current[update.id] = update.state
            snapshots.append(current)
        }
        return snapshots
    }

    @Test func listsCombiningTheFindingsBeforeTheAgentsStart() async throws {
        let snapshots = await run(models: ["opus", "fable"])
        let beforeAgents = try #require(snapshots.first { $0[ReviewEngine.consolidationID] != nil })
        #expect(beforeAgents[ReviewEngine.consolidationID] == .queued)
        #expect(!beforeAgents.values.contains(.running))
        let final = try #require(snapshots.last?[ReviewEngine.consolidationID])
        #expect(final == .done || final == .skipped)
    }

    @Test func oneModelHasNothingToCombine() async {
        let snapshots = await run(models: ["opus"])
        #expect(snapshots.allSatisfy { $0[ReviewEngine.consolidationID] == nil })
    }
}
