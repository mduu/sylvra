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

/// The author's hints: an addition to the review, answered by every agent.
struct ReviewHintTests {
    let shard = ShardPlanner.Shard(name: "Whole PR", files: [])

    @Test func thePromptAsksForAttentionWithoutLimitingTheReview() {
        var request = ReviewRequest(
            pullRequestTitle: "Cache", pullRequestBody: "", shard: shard, repositoryContext: [], history: [],
            model: "opus", effort: "high", language: "English", workingDirectory: nil)
        #expect(!request.prompt.contains("## Reviewer hints"))
        request.hints = ["thread safety of the cache", "keep the migration backwards compatible"]
        let prompt = request.prompt
        #expect(prompt.contains("## Reviewer hints"))
        #expect(prompt.contains("Review the whole change as usual"))
        #expect(prompt.contains("1. thread safety of the cache\n2. keep the migration backwards compatible"))
        #expect(ReviewRequest.outputSchema.contains("\"hints\":{\"type\":\"array\""))
    }

    @Test func everyAgentsAnswerIsKeptPerHint() throws {
        func output(_ json: String) throws -> AgentReviewOutput {
            try JSONDecoder().decode(AgentReviewOutput.self, from: Data(json.utf8))
        }
        let opus = try output(
            """
            {"summary":"","findings":[],"hints":[{"hint":"Thread safety  of the cache","answer":"The lock covers it."}]}
            """)
        // Fable rephrased both hints but answered both: matched by position.
        let fable = try output(
            """
            {"summary":"","findings":[],"hints":[{"hint":"cache threads","answer":"A race in evict()."},
            {"hint":"migration","answer":"Not touched here."}]}
            """)
        let answers = ReviewMerger.hintAnswers(
            ["thread safety of the cache", "the migration stays backwards compatible"],
            outputs: [
                (opus, AgentSource(provider: "Claude Code", model: "opus", effort: "high")),
                (fable, AgentSource(provider: "Claude Code", model: "fable", effort: "high")),
            ])
        #expect(answers.map(\.hint) == ["thread safety of the cache", "the migration stays backwards compatible"])
        #expect(answers[0].answers.map(\.model) == ["opus", "fable"])
        #expect(answers[1].answers == [HintAnswer.Answer(model: "fable", text: "Not touched here.")])
        #expect(
            ReviewMerger.hintAnswers([], outputs: [(opus, AgentSource(provider: "", model: "", effort: ""))]).isEmpty)
    }

    @Test func copiedHintsNameTheModelsAndTheUnanswered() {
        let text = AIReviewClipboard.hints([
            HintAnswer(hint: "thread safety", answers: [.init(model: "opus", text: "The lock covers it.")]),
            HintAnswer(hint: "migration"),
        ])
        #expect(
            text == """
                ## Reviewer hints

                ### thread safety
                - **Opus:** The lock covers it.

                ### migration
                - No reviewer answered this point.
                """)
    }
}
