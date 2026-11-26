import Foundation
import SylvraCore

/// AI review content as Markdown for the clipboard, written to be pasted into a coding agent (e.g. Claude Code
/// in a terminal): full paths with lines instead of file names, severities and verdicts spelled out, suggestions
/// in code blocks, and which pull request it is about.
public enum AIReviewClipboard {
    /// `acme/billing#1234 — Add invoice export`
    public static func pullRequestLine(_ id: PullRequestID?, title: String? = nil) -> String? {
        guard let id else { return nil }
        guard let title, !title.isEmpty else { return "Pull request: \(id)" }
        return "Pull request: \(id) — \(title)"
    }

    public static func summary(
        _ summary: String, risk: RiskAssessment?, mergeability: MergeabilityAssessment? = nil,
        slop: SlopAssessment? = nil, knowledge: KnowledgeAssessment? = nil, readingOrder: [ReadingStep],
        pullRequest: String? = nil
    ) -> String {
        var parts = header("AI summary", pullRequest)
        parts.append(summary.trimmingCharacters(in: .whitespacesAndNewlines))
        if let mergeability {
            parts.append(
                (["Mergeability: \(mergeability.level.label)"] + mergeability.reasons.map { "- \($0)" })
                    .joined(separator: "\n"))
        }
        if let risk {
            parts.append(
                (["Merge risk: \(risk.level.rawValue)"] + risk.reasons.map { "- \($0)" }).joined(separator: "\n"))
        }
        if let slop { parts.append(slopBody(slop)) }
        if let knowledge {
            parts.append(
                (["Worth remembering: \(knowledge.level.label)"] + knowledge.takeaways.map { "- \($0)" })
                    .joined(separator: "\n"))
        }
        if !readingOrder.isEmpty {
            let steps = readingOrder.enumerated().map { index, step in
                let risky = step.isRisky ? " (risky)" : ""
                let reason = step.reason.isEmpty ? "" : " — \(step.reason)"
                return "\(index + 1). `\(step.path)`\(reason)\(risky)"
            }
            parts.append((["Reading order:"] + steps).joined(separator: "\n"))
        }
        return joined(parts)
    }

    public static func overall(_ points: [OverallFinding], pullRequest: String? = nil) -> String {
        var parts = header("Whole pull request", pullRequest)
        parts += points.map { point in
            let line = "- **\(point.kind.label): \(point.title)**"
            return point.rationale.isEmpty ? line : line + "\n  " + point.rationale
        }
        return joined(parts)
    }

    public static func finding(_ finding: ReviewFinding, pullRequest: String? = nil) -> String {
        joined(header(nil, pullRequest) + [findingBody(finding)])
    }

    public static func findings(
        _ findings: [ReviewFinding], overall: [OverallFinding] = [], pullRequest: String? = nil
    ) -> String {
        var parts = header("AI review findings (\(findings.count))", pullRequest)
        if !overall.isEmpty { parts.append(Self.overall(overall)) }
        parts += findings.map(findingBody)
        return joined(parts)
    }

    /// What the reviewers say about the author's hints, every agent's answer with its model.
    public static func hints(_ hints: [HintAnswer]) -> String {
        joined(
            ["## Reviewer hints"]
                + hints.map { hint in
                    let answers =
                        hint.answers.isEmpty
                        ? ["- No reviewer answered this point."]
                        : hint.answers.map { "- **\($0.model.capitalized):** \($0.text)" }
                    return (["### \(hint.hint)"] + answers).joined(separator: "\n")
                })
    }

    public static func pattern(_ pattern: PatternFinding, pullRequest: String? = nil) -> String {
        joined(header(nil, pullRequest) + [patternBody(pattern)])
    }

    public static func patterns(_ patterns: [PatternFinding], pullRequest: String? = nil) -> String {
        joined(header("Patterns (\(patterns.count))", pullRequest) + patterns.map(patternBody))
    }

    /// One chat message as it was written (answers are Markdown already).
    public static func message(_ message: AIChatModel.Message) -> String {
        var text = message.text.trimmingCharacters(in: .whitespacesAndNewlines)
        if let location = message.location { text = "About `\(location.path)` \(lines(location)):\n\n" + text }
        return text
    }

    /// The whole conversation, question and answer marked.
    public static func chat(_ messages: [AIChatModel.Message], pullRequest: String? = nil) -> String {
        var parts = header("Chat about the pull request", pullRequest)
        parts += messages.map { message in
            let who =
                switch message.role {
                case .user: "**Me:**"
                case .assistant: "**AI:**"
                case .error: "**Error:**"
                }
            return "\(who)\n\(Self.message(message))"
        }
        return joined(parts)
    }

    // MARK: - Parts

    private static func findingBody(_ finding: ReviewFinding) -> String {
        let range =
            finding.startLine == finding.endLine
            ? "line \(finding.startLine)" : "lines \(finding.startLine)–\(finding.endLine)"
        var facts = ["Severity: \(finding.severity.rawValue)"]
        if !finding.category.isEmpty { facts.append("Category: \(finding.category)") }
        if let impact = finding.impact { facts.append("Impact: \(impact.rawValue)") }
        if let likelihood = finding.likelihood { facts.append("Likelihood: \(likelihood.rawValue)") }
        // With several models, how many agreed is part of the finding's weight.
        let models = Array(Set(finding.sources.map(\.model))).sorted()
        if !models.isEmpty { facts.append("Found by: \(models.joined(separator: " + "))") }
        var parts = [
            "### \(finding.title)",
            "File: `\(finding.path)` \(range)" + (finding.isAnchored ? "" : " (not in the diff)"),
            facts.joined(separator: " · "),
            finding.rationale.trimmingCharacters(in: .whitespacesAndNewlines),
        ]
        if let suggestion = finding.suggestion, !suggestion.isEmpty {
            parts.append("Suggested change:\n```\(fence(for: finding.path))\n\(suggestion)\n```")
        }
        return parts.filter { !$0.isEmpty }.joined(separator: "\n")
    }

    private static func slopBody(_ slop: SlopAssessment) -> String {
        var lines = ["Signs of unreviewed code (slop): \(slop.level.rawValue)"]
        for sign in slop.signs {
            var line = "- \(sign.title)"
            if !sign.rationale.isEmpty { line += " — \(sign.rationale)" }
            if !sign.evidence.isEmpty {
                line += " (" + sign.evidence.map { "`\($0.path)` \(range($0))" }.joined(separator: ", ") + ")"
            }
            lines.append(line)
        }
        return lines.joined(separator: "\n")
    }

    private static func patternBody(_ pattern: PatternFinding) -> String {
        var lines = ["### \(pattern.name) — \(pattern.verdict.rawValue)"]
        if !pattern.rationale.isEmpty { lines.append(pattern.rationale) }
        if !pattern.evidence.isEmpty {
            lines.append("Evidence:")
            lines += pattern.evidence.map { "- `\($0.path)` \(range($0))" }
        }
        return lines.joined(separator: "\n")
    }

    private static func header(_ title: String?, _ pullRequest: String?) -> [String] {
        [title.map { "## \($0)" }, pullRequest].compactMap { $0 }
    }

    private static func joined(_ parts: [String]) -> String {
        parts.filter { !$0.isEmpty }.joined(separator: "\n\n")
    }

    private static func range(_ location: CodeLocationText) -> String {
        location.startLine == location.endLine
            ? "line \(location.startLine)" : "lines \(location.startLine)–\(location.endLine)"
    }

    private static func lines(_ location: CodeLocation) -> String {
        let lines = location.lines
        return lines.count == 1 ? "line \(lines.lowerBound)" : "lines \(lines.lowerBound)–\(lines.upperBound)"
    }

    /// The code fence's language from the file extension (helps the agent read the suggestion).
    static func fence(for path: String) -> String {
        let languages = [
            "swift": "swift", "cs": "csharp", "ts": "typescript", "tsx": "tsx", "js": "javascript",
            "jsx": "jsx", "py": "python", "kt": "kotlin", "java": "java", "go": "go", "rb": "ruby", "rs": "rust",
            "sql": "sql", "json": "json", "yml": "yaml", "yaml": "yaml", "sh": "bash", "css": "css", "html": "html",
            "xml": "xml", "md": "markdown",
        ]
        return languages[(path as NSString).pathExtension.lowercased()] ?? ""
    }
}

extension KnowledgeLevel {
    /// English label for copied text and the command line tool.
    public var label: String {
        switch self {
        case .notable: "notable — changes behaviour or usage"
        case .minor: "minor detail"
        case .routine: "routine — nothing to remember"
        }
    }
}

extension Mergeability {
    /// English label for copied text and the command line tool.
    public var label: String {
        switch self {
        case .excellent: "excellent"
        case .good: "good"
        case .acceptable: "acceptable"
        case .notMergeable: "not mergeable"
        }
    }
}

extension OverallFinding.Kind {
    /// English label for copied text (agents read English best; the UI title is localized).
    var label: String {
        switch self {
        case .simpler: "Could be simpler"
        case .tooMuchCode: "Too much code"
        case .scattered: "Too scattered"
        case .other: "Whole change"
        }
    }
}
