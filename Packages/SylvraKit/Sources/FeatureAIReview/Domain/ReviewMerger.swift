import Foundation
import SylvraCore

/// Validates agent output against the diff and merges shards / models (see specs/architecture.md §8.4–8.5).
public enum ReviewMerger {
    public static func merge(_ outputs: [(AgentReviewOutput, AgentSource)], files: [ReviewableFile]) -> ReviewResult {
        let byPath = Dictionary(files.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var findings: [ReviewFinding] = []
        var patterns: [PatternFinding] = []
        var summaries: [String] = []
        var history: [String] = []
        var readingOrder: [ReadingStep] = []

        for (output, source) in outputs {
            summaries.append(output.summary)
            history += output.history ?? []
            // Shards cover different files: keep each agent's order, first mention wins; only files of the PR.
            for step in output.readingOrder ?? [] where byPath[step.path] != nil {
                guard !readingOrder.contains(where: { $0.path == step.path }) else { continue }
                readingOrder.append(
                    ReadingStep(path: step.path, reason: step.reason ?? "", isRisky: step.risky ?? false))
            }
            for raw in output.findings {
                let finding = anchor(raw, source: source, file: byPath[raw.path])
                if let index = findings.firstIndex(where: { isDuplicate($0, finding) }) {
                    if !findings[index].sources.contains(source) { findings[index].sources.append(source) }
                } else {
                    findings.append(finding)
                }
            }
            for raw in output.patterns ?? [] {
                let pattern = PatternFinding(
                    name: raw.name, verdict: raw.verdict, rationale: raw.rationale ?? "",
                    evidence: (raw.evidence ?? []).compactMap { evidence in
                        guard let path = evidence.path, let start = evidence.startLine else { return nil }
                        return CodeLocationText(path: path, startLine: start, endLine: evidence.endLine ?? start)
                    })
                if !patterns.contains(where: {
                    $0.name.caseInsensitiveCompare(pattern.name) == .orderedSame && $0.verdict == pattern.verdict
                }) {
                    patterns.append(pattern)
                }
            }
        }
        findings.sort { ($0.severity, $0.path, $0.startLine) < ($1.severity, $1.path, $1.startLine) }
        return ReviewResult(
            summary: summaries.filter { !$0.isEmpty }.joined(separator: "\n\n"), findings: findings, patterns: patterns,
            history: Array(Set(history)).sorted(), readingOrder: readingOrder)
    }

    /// Re-anchors findings outside the diff to the nearest visible line, or marks them unanchored.
    static func anchor(_ raw: AgentReviewOutput.Finding, source: AgentSource, file: ReviewableFile?) -> ReviewFinding {
        var start = raw.startLine
        var end = raw.endLine ?? raw.startLine
        var anchored = false
        if let file {
            end = min(max(end, start), start + 500)  // never trust an agent-supplied range blindly
            if file.visibleNewLines.contains(where: { (start...end).contains($0) }) {
                anchored = true
            } else if let nearest = file.visibleNewLines.min(by: { abs($0 - start) < abs($1 - start) }),
                abs(nearest - start) <= 5
            {
                start = nearest
                end = nearest
                anchored = true
            }
        }
        return ReviewFinding(
            path: raw.path, startLine: start, endLine: end, severity: raw.severity, category: raw.category ?? "design",
            title: raw.title, rationale: raw.rationale ?? "", suggestion: raw.suggestion?.nilIfEmpty,
            confidence: raw.confidence ?? 0.5, sources: [source], isAnchored: anchored)
    }

    /// Same file, overlapping lines and a similar title.
    static func isDuplicate(_ lhs: ReviewFinding, _ rhs: ReviewFinding) -> Bool {
        guard lhs.path == rhs.path, lhs.startLine <= rhs.endLine + 2, rhs.startLine <= lhs.endLine + 2 else {
            return false
        }
        let lhsWords = Set(lhs.title.lowercased().split(whereSeparator: { !$0.isLetter }).filter { $0.count > 3 })
        let rhsWords = Set(rhs.title.lowercased().split(whereSeparator: { !$0.isLetter }).filter { $0.count > 3 })
        guard !lhsWords.isEmpty, !rhsWords.isEmpty else { return lhs.category == rhs.category }
        return Double(lhsWords.intersection(rhsWords).count) / Double(min(lhsWords.count, rhsWords.count)) >= 0.4
            || (lhs.category == rhs.category && lhs.startLine == rhs.startLine)
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
