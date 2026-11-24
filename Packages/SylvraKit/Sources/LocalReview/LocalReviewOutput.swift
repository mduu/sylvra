import FeatureAIReview
import Foundation

/// The result of `sylvra review` as Markdown (people and coding agents) or JSON (scripts).
public enum LocalReviewOutput {
    public static func render(_ report: LocalReviewReport, format: LocalReviewOptions.Format) throws -> String {
        switch format {
        case .markdown: markdown(report)
        case .json: try json(report)
        }
    }

    public static func markdown(_ report: LocalReviewReport) -> String {
        let changes = report.changes
        let scope = changes.includesUncommitted ? "commits, uncommitted and new files" : "commits only"
        var parts = [
            "# Sylvra AI review: \(changes.branch ?? "HEAD") against \(changes.base)",
            """
            Reviewed \(report.fileCount) file(s) (\(scope)) with \(report.settings.models.joined(separator: " + ")), \
            effort \(report.settings.effort). Findings are suggestions from AI agents: check each against the code \
            before changing anything.
            """,
        ]
        guard let result = report.result else {
            parts.append("No changes to review against \(changes.base).")
            return parts.joined(separator: "\n\n") + "\n"
        }
        if !result.summary.isEmpty || result.risk != nil || result.mergeability != nil {
            parts.append(
                AIReviewClipboard.summary(
                    result.summary, risk: result.risk, mergeability: result.mergeability, slop: result.slop,
                    readingOrder: result.readingOrder))
        }
        if !result.hints.isEmpty { parts.append(AIReviewClipboard.hints(result.hints)) }
        if result.findings.isEmpty, result.overall.isEmpty {
            parts.append("## AI review findings\n\nNo findings.")
        } else {
            parts.append(AIReviewClipboard.findings(sorted(result.findings), overall: result.overall))
        }
        if !result.patterns.isEmpty { parts.append(AIReviewClipboard.patterns(result.patterns)) }
        if !report.failures.isEmpty {
            parts.append(
                "## Agents that failed\n\nTheir part is missing from this review.\n"
                    + report.failures.map { "- \($0)" }.joined(separator: "\n"))
        }
        return parts.joined(separator: "\n\n") + "\n"
    }

    /// Most severe first, then by file and line.
    static func sorted(_ findings: [ReviewFinding]) -> [ReviewFinding] {
        findings.sorted { ($0.severity, $0.path, $0.startLine) < ($1.severity, $1.path, $1.startLine) }
    }

    public static func json(_ report: LocalReviewReport) throws -> String {
        let document = Document(
            base: report.changes.base, branch: report.changes.branch,
            includesUncommitted: report.changes.includesUncommitted, files: report.fileCount,
            settings: .init(
                models: report.settings.models, effort: report.settings.effort,
                agents: report.settings.maxParallelAgents, language: report.settings.agentLanguage),
            result: report.result, failures: report.failures)
        let encoder = JSONEncoder()
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes]
        encoder.dateEncodingStrategy = .iso8601
        return String(decoding: try encoder.encode(document), as: UTF8.self) + "\n"
    }

    private struct Document: Encodable {
        struct Settings: Encodable {
            let models: [String]
            let effort: String
            let agents: Int
            let language: String
        }
        let base: String
        let branch: String?
        let includesUncommitted: Bool
        let files: Int
        let settings: Settings
        let result: ReviewResult?
        let failures: [String]
    }

}
