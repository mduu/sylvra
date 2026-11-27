import Foundation
import Testing

@testable import FeatureAIReview

/// Whether a change is worth remembering, and what: one more step toward trusting the system.
struct KnowledgeTests {
    private let file = ReviewableFile(
        path: "A.swift", patch: "@@ -1 +1 @@\n+x", changedNewLines: [10], visibleNewLines: Set(5...15), isNoise: false)
    private let opus = AgentSource(provider: "c", model: "opus", effort: "m")

    private func output(_ knowledge: String) throws -> AgentReviewOutput {
        let json = #"{"summary":"s","findings":[],"patterns":[],"knowledge":"# + knowledge + "}"
        return try JSONDecoder().decode(AgentReviewOutput.self, from: Data(json.utf8))
    }

    @Test func theMostNotableRatingWinsWithItsTakeawaysOnce() throws {
        let routine = try output(#"{"level":"routine","takeaways":["Renamed a helper"]}"#)
        let notable = try output(
            #"{"level":"notable","takeaways":["Invoices now round VAT per invoice, not per line."]}"#)
        let minor = try output(
            #"{"level":"minor","takeaways":["Invoices round VAT per invoice, not per line now.","Default page size is 50."]}"#
        )
        let result = ReviewMerger.merge([(routine, opus), (notable, opus), (minor, opus)], files: [file])
        // Said twice in other words: once. A routine shard's notes don't count.
        #expect(
            result.knowledge
                == KnowledgeAssessment(
                    level: .notable,
                    takeaways: ["Invoices now round VAT per invoice, not per line.", "Default page size is 50."]))
    }

    @Test func takeawaysSayWhetherTheyAreDomainOrTechnical() throws {
        let rated = try output(
            #"{"level":"notable","takeaways":[{"kind":"domain","text":"VAT is rounded per invoice."},"#
                + #"{"kind":"technical","text":"Exports run in a queue."}]}"#)
        let result = ReviewMerger.merge([(rated, opus)], files: [file])
        #expect(
            result.knowledge?.takeaways == [
                Takeaway("VAT is rounded per invoice.", kind: .domain),
                Takeaway("Exports run in a queue.", kind: .technical),
            ])
        #expect(
            result.knowledge?.takeaways.map(\.line) == [
                "[domain] VAT is rounded per invoice.", "[technical] Exports run in a queue.",
            ])
        #expect(ReviewRequest.outputSchema.contains(#""technical""#))
    }

    @Test func olderReviewsWithPlainTakeawaysStillLoad() throws {
        let older = #"{"level":"minor","takeaways":["Default page size is 50."]}"#
        let knowledge = try JSONDecoder().decode(KnowledgeAssessment.self, from: Data(older.utf8))
        #expect(knowledge.takeaways == [Takeaway("Default page size is 50.")])
        let tagged = KnowledgeAssessment(level: .minor, takeaways: [Takeaway("Limit is 10.", kind: .technical)])
        #expect(try JSONDecoder().decode(KnowledgeAssessment.self, from: JSONEncoder().encode(tagged)) == tagged)
    }

    @Test func routineChangesHaveNothingToRemember() throws {
        let result = ReviewMerger.merge(
            [(try output(#"{"level":"routine","takeaways":["Formatting"]}"#), opus)], files: [file])
        #expect(result.knowledge == KnowledgeAssessment(level: .routine))
    }

    @Test func schemaAndPromptAskForIt() throws {
        #expect(ReviewRequest.outputSchema.contains(#""knowledge""#))
        #expect(ReviewRequest.outputSchema.contains(#""takeaways""#))
        _ = try JSONSerialization.jsonObject(with: Data(ReviewRequest.outputSchema.utf8))
    }

    @Test func survivesTheCacheAndOlderReviewsLoad() throws {
        var result = ReviewResult(summary: "s")
        result.knowledge = KnowledgeAssessment(level: .minor, takeaways: ["Default page size is 50."])
        #expect(try JSONDecoder().decode(ReviewResult.self, from: JSONEncoder().encode(result)) == result)
        let older = #"{"summary":"s","findings":[],"patterns":[],"history":[]}"#
        #expect(try JSONDecoder().decode(ReviewResult.self, from: Data(older.utf8)).knowledge == nil)
    }

    @Test func theCopiedSummarySaysWhatToRemember() {
        let text = AIReviewClipboard.summary(
            "Rounds VAT per invoice.", risk: nil,
            knowledge: KnowledgeAssessment(level: .notable, takeaways: ["Invoices round VAT per invoice."]),
            readingOrder: [])
        #expect(
            text.hasSuffix(
                "Worth remembering: notable — domain knowledge or a fundamental technical change\n- Invoices round VAT per invoice."
            )
        )
    }
}
