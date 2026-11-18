import Foundation
import Testing

@testable import FeatureAIReview

struct RiskTests {
    private let file = ReviewableFile(
        path: "A.swift", patch: "@@ -1 +1 @@\n+x", changedNewLines: [10], visibleNewLines: Set(5...15), isNoise: false)

    private func output(_ json: String) throws -> AgentReviewOutput {
        try JSONDecoder().decode(AgentReviewOutput.self, from: Data(json.utf8))
    }

    @Test func takesTheHighestRiskAndKeepsItsReasonsFirst() throws {
        let low = try output(
            #"{"summary":"s","risk":{"level":"low","reasons":["Docs only","Shared"]},"findings":[],"patterns":[]}"#)
        let high = try output(
            #"{"summary":"s","risk":{"level":"high","reasons":["Totals change","Shared"]},"findings":[],"patterns":[]}"#
        )
        let opus = AgentSource(provider: "c", model: "opus", effort: "m")
        let result = ReviewMerger.merge([(low, opus), (high, opus)], files: [file])
        #expect(result.risk == RiskAssessment(level: .high, reasons: ["Totals change", "Shared", "Docs only"]))
        // Regression: identical summaries of two models were shown twice.
        #expect(result.summary == "s")
    }

    @Test func duplicateFindingsKeepTheHigherImpactAndLikelihood() throws {
        func finding(_ impact: String, _ likelihood: String) -> String {
            #"{"summary":"s","findings":[{"path":"A.swift","startLine":10,"endLine":10,"severity":"major","#
                + #""category":"bug","title":"Rounding drifts totals","rationale":"r","confidence":0.8,"#
                + #""impact":"\#(impact)","likelihood":"\#(likelihood)"}],"patterns":[]}"#
        }
        let result = ReviewMerger.merge(
            [
                (try output(finding("medium", "high")), AgentSource(provider: "c", model: "opus", effort: "m")),
                (try output(finding("high", "low")), AgentSource(provider: "c", model: "fable", effort: "m")),
            ], files: [file])
        #expect(result.findings.count == 1)
        #expect(result.findings.first?.impact == .high)
        #expect(result.findings.first?.likelihood == .high)
    }

    @Test func reviewsWithoutRiskStillLoad() throws {
        let json =
            #"{"summary":"s","findings":[{"id":"\#(UUID().uuidString)","path":"A.swift","startLine":1,"#
            + #""endLine":1,"severity":"minor","category":"bug","title":"t","rationale":"r","confidence":0.5,"#
            + #""sources":[],"isAnchored":true}],"patterns":[],"history":[]}"#
        let result = try JSONDecoder().decode(ReviewResult.self, from: Data(json.utf8))
        #expect(result.risk == nil)
        #expect(result.findings.first?.impact == nil)
        #expect(ReviewMerger.merge([], files: []).risk == nil)
    }

    @Test func schemaAndPromptAskForRisk() {
        #expect(ReviewRequest.outputSchema.contains(#""risk""#))
        #expect(ReviewRequest.outputSchema.contains(#""likelihood""#))
        let data = Data(ReviewRequest.outputSchema.utf8)
        #expect((try? JSONSerialization.jsonObject(with: data)) != nil)
    }
}
