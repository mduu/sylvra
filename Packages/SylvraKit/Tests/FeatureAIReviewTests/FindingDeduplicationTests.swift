import Foundation
import SylvraCore
import Testing

@testable import FeatureAIReview

/// Findings two models (or shards) report for the same problem become one; different problems stay apart.
struct FindingDeduplicationTests {
    private func finding(
        _ title: String, line: Int, endLine: Int? = nil, category: String = "bug", rationale: String = ""
    ) -> ReviewFinding {
        ReviewFinding(
            path: "a.swift", startLine: line, endLine: endLine ?? line, severity: .major, category: category,
            title: title, rationale: rationale, suggestion: nil, confidence: 0.8, impact: nil, likelihood: nil,
            sources: [], isAnchored: true)
    }

    @Test func mergesInflectedWordingInTheAgentLanguage() {
        #expect(
            ReviewMerger.isDuplicate(
                finding("Rundung der Positionen verfälscht die Rechnungssumme", line: 10),
                finding("Gerundete Positionen verfälschen die Rechnungssummen", line: 11)))
    }

    @Test func mergesTheCauseAndTheEffectAFewLinesApart() {
        #expect(
            ReviewMerger.isDuplicate(
                finding("Invoice total drifts by rounding each item", line: 8),
                finding("Rounding each item makes the invoice total drift", line: 14)))
    }

    @Test func mergesDifferentTitlesWithTheSameReasoning() {
        #expect(
            ReviewMerger.isDuplicate(
                finding(
                    "Totals change for existing invoices", line: 9,
                    rationale: "Each item is rounded before summing, so totals drift by cents"),
                finding(
                    "Per-item rounding changes invoice totals", line: 10,
                    rationale: "Rounding every item before summing makes totals drift a few cents")))
    }

    @Test func keepsDifferentProblemsOnTheSameLines() {
        #expect(
            !ReviewMerger.isDuplicate(
                finding("Missing null check for the customer", line: 10),
                finding("Log message leaks the customer's email", line: 10, category: "security")))
        #expect(
            !ReviewMerger.isDuplicate(
                finding("Missing null check for the customer", line: 10),
                finding("Rounding changes invoice totals", line: 14)))
    }

    @Test func keepsTheSameWordingFarApart() {
        #expect(
            !ReviewMerger.isDuplicate(
                finding("Rounding changes invoice totals", line: 10),
                finding("Rounding changes invoice totals", line: 40)
            ))
    }
}
