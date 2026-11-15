import Foundation

/// Canned findings for `--demo` (matches the demo diff of `FeatureDiff`).
public struct DemoAgentProvider: AgentProvider {
    public let name = "Claude Code"
    private let delay: Duration

    public init(delay: Duration = .milliseconds(900)) {
        self.delay = delay
    }

    public func detectVersion() async -> String? { "2.1 (demo)" }

    public func review(_ request: ReviewRequest) async throws -> AgentReviewOutput {
        try await Task.sleep(for: delay)
        let json = """
            {"summary": "Adds CSV export next to JSON and changes how invoice totals are summed. The rounding change \
            affects every existing invoice — that is where the risk is.",
             "findings": [
              {"path": "Sources/Billing/InvoiceService.swift", "startLine": 9, "endLine": 9, "severity": "major",
               "category": "bug", "title": "Rounding per line item changes invoice totals",
               "rationale": "Each item is rounded before summing. With many small items the total drifts by several \
            cents compared to today and to the PDF export. Round once, after summing.",
               "suggestion": "            sum + item.price * item.quantity", "confidence": 0.86},
              {"path": "Sources/Export/CSVEncoder.swift", "startLine": 8, "endLine": 8, "severity": "major",
               "category": "security", "title": "CSV values are not escaped",
               "rationale": "Names containing commas, quotes or newlines break the CSV and allow formula injection \
            when opened in Excel.", "confidence": 0.8},
              {"path": "Tests/BillingTests/InvoiceServiceTests.swift", "startLine": 16, "endLine": 19, "severity": "minor",
               "category": "tests", "title": "No test for rounding of many small items",
               "rationale": "The changed rounding behaviour is not covered.", "confidence": 0.7},
              {"path": "Sources/Export/ExportFormat.swift", "startLine": 1, "endLine": 1, "severity": "nit",
               "category": "style", "title": "ExportFormat could be CaseIterable",
               "rationale": "Allows listing formats in the UI without duplication.", "confidence": 0.5}
             ],
             "patterns": [
              {"name": "Service layer", "verdict": "followed", "rationale": "Logic stays in InvoiceService."},
              {"name": "Single rounding point", "verdict": "violated", "rationale": "specs/billing.md requires rounding \
            only on the invoice total.", "evidence": [{"path": "Sources/Billing/InvoiceService.swift", "startLine": 9}]},
              {"name": "Encoder strategy", "verdict": "introduced", "rationale": "ExportFormat selects the encoder."}
             ],
             "history": ["#812 “Fix VAT rounding” changed the same total calculation — this PR partly reverts it."]}
            """
        return try JSONDecoder().decode(AgentReviewOutput.self, from: Data(json.utf8))
    }
}
