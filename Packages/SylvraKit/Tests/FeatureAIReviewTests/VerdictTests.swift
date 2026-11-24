import Foundation
import Testing

@testable import FeatureAIReview

struct VerdictTests {
    private let file = ReviewableFile(
        path: "A.swift", patch: "@@ -1 +1 @@\n+x", changedNewLines: [10], visibleNewLines: Set(5...15), isNoise: false)
    private let opus = AgentSource(provider: "c", model: "opus", effort: "m")

    private func output(_ verdicts: String) throws -> AgentReviewOutput {
        let json = #"{"summary":"s","findings":[],"patterns":[],"# + verdicts + "}"
        return try JSONDecoder().decode(AgentReviewOutput.self, from: Data(json.utf8))
    }

    @Test func theLowestMergeabilityWinsWithItsReasonsFirst() throws {
        let good = try output(#""mergeability":{"level":"good","reasons":["Clean","Tested"]}"#)
        let blocked = try output(#""mergeability":{"level":"notMergeable","reasons":["Drops data","Tested"]}"#)
        let result = ReviewMerger.merge([(good, opus), (blocked, opus)], files: [file])
        #expect(
            result.mergeability
                == MergeabilityAssessment(level: .notMergeable, reasons: ["Drops data", "Tested", "Clean"]))
    }

    @Test func theHighestSlopWinsAndSimilarSignsShareTheirEvidence() throws {
        let some = try output(
            #""slop":{"level":"some","signs":[{"title":"Comments restate the code","rationale":"r","#
                + #""evidence":[{"path":"A.swift","startLine":6,"endLine":7}]}]}"#)
        let many = try output(
            #""slop":{"level":"many","signs":[{"title":"Comments restating code","rationale":"r2","#
                + #""evidence":[{"path":"A.swift","startLine":12,"endLine":12},"#
                + #"{"path":"Elsewhere.swift","startLine":1,"endLine":1}]},"#
                + #"{"title":"Tests assert nothing","rationale":"r3","evidence":[]}]}"#)
        let slop = try #require(ReviewMerger.merge([(some, opus), (many, opus)], files: [file]).slop)
        #expect(slop.level == .many)
        #expect(slop.suggestsSendingBack)
        #expect(slop.signs.map(\.title) == ["Comments restating code", "Tests assert nothing"])
        // Evidence outside the pull request's files is dropped.
        #expect(
            slop.signs.first?.evidence == [
                CodeLocationText(path: "A.swift", startLine: 12, endLine: 12),
                CodeLocationText(path: "A.swift", startLine: 6, endLine: 7),
            ])
    }

    @Test func reviewsWithoutVerdictsStillLoad() throws {
        let json = #"{"summary":"s","findings":[],"patterns":[],"history":[]}"#
        let result = try JSONDecoder().decode(ReviewResult.self, from: Data(json.utf8))
        #expect(result.mergeability == nil)
        #expect(result.slop == nil)
        #expect(ReviewMerger.merge([(try output(#""risk":null"#), opus)], files: [file]).mergeability == nil)
    }

    @Test func verdictsSurviveTheCache() throws {
        var result = ReviewResult(summary: "s")
        result.mergeability = MergeabilityAssessment(level: .acceptable, reasons: ["Needs tests"])
        result.slop = SlopAssessment(level: .some, signs: [SlopSign(title: "t", rationale: "r")])
        let decoded = try JSONDecoder().decode(ReviewResult.self, from: JSONEncoder().encode(result))
        #expect(decoded == result)
    }

    @Test func schemaAndPromptAskForTheVerdicts() throws {
        #expect(ReviewRequest.outputSchema.contains(#""mergeability""#))
        #expect(ReviewRequest.outputSchema.contains(#""notMergeable""#))
        #expect(ReviewRequest.outputSchema.contains(#""slop""#))
        _ = try JSONSerialization.jsonObject(with: Data(ReviewRequest.outputSchema.utf8))
    }

    @Test func copiedSummaryNamesVerdictAndSlopSigns() {
        let text = AIReviewClipboard.summary(
            "Adds export.", risk: nil,
            mergeability: MergeabilityAssessment(level: .notMergeable, reasons: ["Drops data"]),
            slop: SlopAssessment(
                level: .many,
                signs: [
                    SlopSign(
                        title: "Tests assert nothing", rationale: "Mocks only.",
                        evidence: [CodeLocationText(path: "T.swift", startLine: 3, endLine: 9)])
                ]),
            readingOrder: [])
        #expect(
            text == """
                ## AI summary

                Adds export.

                Mergeability: not mergeable
                - Drops data

                Signs of unreviewed code (slop): many
                - Tests assert nothing — Mocks only. (`T.swift` lines 3–9)
                """)
    }
}
