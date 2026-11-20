import Foundation
import SylvraCore

/// Validates agent output against the diff and merges shards / models (see specs/architecture.md §8.4–8.5).
public enum ReviewMerger {
    public static func merge(_ outputs: [(AgentReviewOutput, AgentSource)], files: [ReviewableFile]) -> ReviewResult {
        let byPath = Dictionary(files.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var findings: [ReviewFinding] = []
        var patterns: [PatternFinding] = []
        var overall: [OverallFinding] = []
        var summaries: [String] = []
        var history: [String] = []
        var readingOrder: [ReadingStep] = []
        var risks: [AgentReviewOutput.Risk] = []

        for (output, source) in outputs {
            // Models that say the same thing don't repeat it.
            if !summaries.contains(output.summary) { summaries.append(output.summary) }
            if let risk = output.risk { risks.append(risk) }
            history += output.history ?? []
            // Shards cover different files: keep each agent's order, first mention wins; only files of the PR.
            for step in output.readingOrder ?? [] where byPath[step.path] != nil {
                guard !readingOrder.contains(where: { $0.path == step.path }) else { continue }
                readingOrder.append(
                    ReadingStep(path: step.path, reason: step.reason ?? "", isRisky: step.risky ?? false))
            }
            for raw in output.findings {
                add(anchor(raw, source: source, file: byPath[raw.path]), to: &findings)
            }
            for raw in output.patterns ?? [] {
                add(pattern(raw, files: byPath), to: &patterns)
            }
            // Shards and models may name the same point; the first wording wins.
            for raw in output.overall ?? []
            where !overall.contains(where: { $0.title.caseInsensitiveCompare(raw.title) == .orderedSame }) {
                overall.append(
                    OverallFinding(
                        kind: raw.kind.flatMap(OverallFinding.Kind.init(rawValue:)) ?? .other, title: raw.title,
                        rationale: raw.rationale ?? ""))
            }
        }
        findings.sort { ($0.severity, $0.path, $0.startLine) < ($1.severity, $1.path, $1.startLine) }
        var result = ReviewResult(
            summary: summaries.filter { !$0.isEmpty }.joined(separator: "\n\n"), findings: findings, patterns: patterns,
            history: Array(Set(history)).sorted(), readingOrder: readingOrder, risk: overallRisk(risks))
        result.overall = overall
        return result
    }

    /// A new finding, or another source (and the higher ratings) for one already reported.
    private static func add(_ finding: ReviewFinding, to findings: inout [ReviewFinding]) {
        guard let index = findings.firstIndex(where: { isDuplicate($0, finding) }) else {
            findings.append(finding)
            return
        }
        for source in finding.sources where !findings[index].sources.contains(source) {
            findings[index].sources.append(source)
        }
        // Agents that agree on a finding may rate it differently: keep the higher rating.
        findings[index].impact = higher(findings[index].impact, finding.impact)
        findings[index].likelihood = higher(findings[index].likelihood, finding.likelihood)
    }

    /// Evidence only in files of the pull request, so a click on it can show it in the diff.
    private static func pattern(_ raw: AgentReviewOutput.Pattern, files: [String: ReviewableFile]) -> PatternFinding {
        PatternFinding(
            name: raw.name, verdict: raw.verdict, rationale: raw.rationale ?? "",
            evidence: (raw.evidence ?? []).compactMap { evidence in
                guard let path = evidence.path, files[path] != nil, let start = evidence.startLine else { return nil }
                return CodeLocationText(path: path, startLine: start, endLine: evidence.endLine ?? start)
            })
    }

    /// A new pattern, or more evidence for one already reported (other shards see other files).
    private static func add(_ pattern: PatternFinding, to patterns: inout [PatternFinding]) {
        guard
            let index = patterns.firstIndex(where: {
                $0.name.caseInsensitiveCompare(pattern.name) == .orderedSame && $0.verdict == pattern.verdict
            })
        else {
            patterns.append(pattern)
            return
        }
        let added = pattern.evidence.filter { !patterns[index].evidence.contains($0) }
        guard !added.isEmpty else { return }
        patterns[index] = PatternFinding(
            name: patterns[index].name, verdict: patterns[index].verdict, rationale: patterns[index].rationale,
            evidence: patterns[index].evidence + added)
    }

    /// The highest rating of all shards and models; its reasons first, at most four, without repeats.
    static func overallRisk(_ risks: [AgentReviewOutput.Risk]) -> RiskAssessment? {
        guard let level = risks.map(\.level).max() else { return nil }
        var reasons: [String] = []
        for risk in risks.sorted(by: { $0.level > $1.level }) {
            for reason in risk.reasons ?? [] where !reason.isEmpty && !reasons.contains(reason) {
                reasons.append(reason)
            }
        }
        return RiskAssessment(level: level, reasons: Array(reasons.prefix(4)))
    }

    private static func higher(_ lhs: RiskLevel?, _ rhs: RiskLevel?) -> RiskLevel? {
        [lhs, rhs].compactMap { $0 }.max()
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
            confidence: raw.confidence ?? 0.5, impact: raw.impact, likelihood: raw.likelihood, sources: [source],
            isAnchored: anchored)
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
