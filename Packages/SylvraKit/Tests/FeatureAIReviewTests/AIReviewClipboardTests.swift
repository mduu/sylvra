import Foundation
import SylvraCore
import Testing

@testable import FeatureAIReview

/// Copied AI content is Markdown an agent can act on: full paths, lines, severities, the pull request.
struct AIReviewClipboardTests {
    let pullRequest = AIReviewClipboard.pullRequestLine(
        PullRequestID(owner: "acme", repository: "billing", number: 1234), title: "Add invoice export")

    let finding = ReviewFinding(
        path: "Sources/Billing/InvoiceService.swift", startLine: 9, endLine: 12, severity: .major,
        category: "correctness", title: "Rounding drifts from the invoice total",
        rationale: "Rounding each line before summing can differ from the total by a few cents.",
        suggestion: "let total = items.map(\\.amount).reduce(0, +).rounded(2)", impact: .high, likelihood: .medium)

    @Test func aFindingHasItsFullPathLinesAndSuggestion() {
        let text = AIReviewClipboard.finding(finding, pullRequest: pullRequest)
        #expect(
            text == """
                Pull request: acme/billing#1234 — Add invoice export

                ### Rounding drifts from the invoice total
                File: `Sources/Billing/InvoiceService.swift` lines 9–12
                Severity: major · Category: correctness · Impact: high · Likelihood: medium
                Rounding each line before summing can differ from the total by a few cents.
                Suggested change:
                ```swift
                let total = items.map(\\.amount).reduce(0, +).rounded(2)
                ```
                """)
    }

    @Test func aFindingSaysWhichModelsFoundIt() {
        var found = finding
        found.sources = [
            AgentSource(provider: "Claude Code", model: "opus", effort: "high"),
            AgentSource(provider: "Claude Code", model: "fable", effort: "high"),
        ]
        #expect(AIReviewClipboard.finding(found).contains("Likelihood: medium · Found by: fable + opus"))
    }

    @Test func allFindingsStartWithTheWholePullRequest() {
        let overall = [
            OverallFinding(kind: .scattered, title: "Formats defined twice", rationale: "ExportFormat and CSVEncoder.")
        ]
        let text = AIReviewClipboard.findings([finding], overall: overall, pullRequest: pullRequest)
        #expect(text.hasPrefix("## AI review findings (1)\n\nPull request: acme/billing#1234"))
        #expect(text.contains("- **Too scattered: Formats defined twice**\n  ExportFormat and CSVEncoder."))
        #expect(text.contains("### Rounding drifts from the invoice total"))
    }

    @Test func theSummaryCarriesRiskAndReadingOrder() {
        let text = AIReviewClipboard.summary(
            "Adds CSV export.", risk: RiskAssessment(level: .medium, reasons: ["Totals change"]),
            readingOrder: [ReadingStep(path: "Sources/Billing/InvoiceService.swift", reason: "Core", isRisky: true)])
        #expect(
            text == """
                ## AI summary

                Adds CSV export.

                Merge risk: medium
                - Totals change

                Reading order:
                1. `Sources/Billing/InvoiceService.swift` — Core (risky)
                """)
    }

    @Test func patternsListTheirEvidence() {
        let pattern = PatternFinding(
            name: "Repository pattern", verdict: .violated, rationale: "Queries in the view model.",
            evidence: [CodeLocationText(path: "Sources/App/InvoiceViewModel.swift", startLine: 40, endLine: 40)])
        #expect(
            AIReviewClipboard.pattern(pattern) == """
                ### Repository pattern — violated
                Queries in the view model.
                Evidence:
                - `Sources/App/InvoiceViewModel.swift` line 40
                """)
    }

    @Test func aChatMarksWhoSaidWhat() {
        let messages = [
            AIChatModel.Message(
                role: .user, text: "Is the rounding right?",
                location: CodeLocation(
                    path: "Sources/Billing/InvoiceService.swift", line: 12, side: .right, startLine: 9)),
            AIChatModel.Message(role: .assistant, text: "Mostly — see **line 10**."),
        ]
        let text = AIReviewClipboard.chat(messages, pullRequest: pullRequest)
        #expect(
            text == """
                ## Chat about the pull request

                Pull request: acme/billing#1234 — Add invoice export

                **Me:**
                About `Sources/Billing/InvoiceService.swift` lines 9–12:

                Is the rounding right?

                **AI:**
                Mostly — see **line 10**.
                """)
    }
}
