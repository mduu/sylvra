import Foundation
import SylvraCore

/// Validates agent output against the diff and merges shards / models (see specs/architecture.md §8.4–8.5).
public enum ReviewMerger {
    /// Every agent's answer to each of the author's hints, in the hints' order. Answers are matched by the hint's
    /// wording; when an agent rephrased its hints but answered all of them, by position.
    public static func hintAnswers(_ hints: [String], outputs: [(AgentReviewOutput, AgentSource)]) -> [HintAnswer] {
        guard !hints.isEmpty else { return [] }
        func normalized(_ text: String) -> String {
            text.lowercased().split(whereSeparator: \.isWhitespace).joined(separator: " ")
        }
        let keys = hints.map(normalized)
        var answers = hints.map { HintAnswer(hint: $0) }
        for (output, source) in outputs {
            let given = output.hints ?? []
            for (position, raw) in given.enumerated() {
                let text = raw.answer.trimmingCharacters(in: .whitespacesAndNewlines)
                guard !text.isEmpty else { continue }
                let index =
                    keys.firstIndex(of: normalized(raw.hint)) ?? (given.count == hints.count ? position : nil)
                guard let index else { continue }
                answers[index].answers.append(HintAnswer.Answer(model: source.model, text: text))
            }
        }
        return answers
    }

    public static func merge(_ outputs: [(AgentReviewOutput, AgentSource)], files: [ReviewableFile]) -> ReviewResult {
        let byPath = Dictionary(files.map { ($0.path, $0) }, uniquingKeysWith: { first, _ in first })
        var findings: [ReviewFinding] = []
        var patterns: [PatternFinding] = []
        var overall: [OverallFinding] = []
        var summaries: [String] = []
        var history: [String] = []
        var readingOrder: [ReadingStep] = []

        for (output, source) in outputs {
            // Models that say the same thing don't repeat it.
            if !summaries.contains(output.summary) { summaries.append(output.summary) }
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
            // Shards and models may name the same point in other words; the first wording wins.
            for raw in output.overall ?? []
            where !overall.contains(where: { overlap(stems($0.title), stems(raw.title)) >= 0.6 }) {
                overall.append(
                    OverallFinding(
                        kind: raw.kind.flatMap(OverallFinding.Kind.init(rawValue:)) ?? .other, title: raw.title,
                        rationale: raw.rationale ?? ""))
            }
        }
        findings.sort { ($0.severity, $0.path, $0.startLine) < ($1.severity, $1.path, $1.startLine) }
        var result = ReviewResult(
            summary: summaries.filter { !$0.isEmpty }.joined(separator: "\n\n"), findings: findings, patterns: patterns,
            history: Array(Set(history)).sorted(), readingOrder: readingOrder,
            risk: overallRisk(outputs.compactMap(\.0.risk)))
        result.overall = overall
        result.mergeability = overallMergeability(outputs.compactMap(\.0.mergeability))
        result.slop = overallSlop(outputs.compactMap(\.0.slop), files: byPath)
        result.knowledge = overallKnowledge(outputs.compactMap(\.0.knowledge))
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

    /// The lowest verdict of all shards and models (a blocker anywhere blocks the whole change); its reasons
    /// first, at most four, without repeats.
    static func overallMergeability(_ verdicts: [AgentReviewOutput.MergeVerdict]) -> MergeabilityAssessment? {
        guard let level = verdicts.map(\.level).min() else { return nil }
        var reasons: [String] = []
        for verdict in verdicts.sorted(by: { $0.level < $1.level }) {
            for reason in verdict.reasons ?? [] where !reason.isEmpty && !reasons.contains(reason) {
                reasons.append(reason)
            }
        }
        return MergeabilityAssessment(level: level, reasons: Array(reasons.prefix(4)))
    }

    /// The highest knowledge rating of all shards and models (one shard's notable change makes the change
    /// notable); takeaways said in other words by another agent once, at most four.
    static func overallKnowledge(_ ratings: [AgentReviewOutput.Knowledge]) -> KnowledgeAssessment? {
        guard let level = ratings.map(\.level).max() else { return nil }
        var takeaways: [Takeaway] = []
        for rating in ratings.sorted(by: { $0.level > $1.level }) where rating.level != .routine {
            for takeaway in rating.takeaways ?? []
            where !takeaway.text.isEmpty
                && !takeaways.contains(where: { overlap(stems($0.text), stems(takeaway.text)) >= 0.6 })
            {
                takeaways.append(takeaway)
            }
        }
        return KnowledgeAssessment(level: level, takeaways: level == .routine ? [] : Array(takeaways.prefix(4)))
    }

    /// The highest slop level of all shards and models; signs named in other words by another agent are merged
    /// (more evidence), evidence only in files of the pull request, at most eight signs.
    static func overallSlop(_ slops: [AgentReviewOutput.Slop], files: [String: ReviewableFile]) -> SlopAssessment? {
        guard let level = slops.map(\.level).max() else { return nil }
        var signs: [SlopSign] = []
        for raw in slops.sorted(by: { $0.level > $1.level }).flatMap({ $0.signs ?? [] }) {
            let evidence = (raw.evidence ?? []).compactMap { evidence -> CodeLocationText? in
                guard let path = evidence.path, files[path] != nil, let start = evidence.startLine else { return nil }
                return CodeLocationText(path: path, startLine: start, endLine: evidence.endLine ?? start)
            }
            if let index = signs.firstIndex(where: { overlap(stems($0.title), stems(raw.title)) >= 0.6 }) {
                signs[index].evidence += evidence.filter { !signs[index].evidence.contains($0) }
            } else {
                signs.append(SlopSign(title: raw.title, rationale: raw.rationale ?? "", evidence: evidence))
            }
        }
        return SlopAssessment(level: level, signs: Array(signs.prefix(8)))
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

    /// The same problem reported twice (other models or shards): same file, close lines and similar wording.
    ///
    /// Deliberately cautious, since merging two different problems hides one; what slips through is grouped by
    /// `FindingConsolidator` when several models ran.
    static func isDuplicate(_ lhs: ReviewFinding, _ rhs: ReviewFinding) -> Bool {
        guard lhs.path == rhs.path else { return false }
        // Lines between the two ranges (negative: they overlap).
        let gap = max(lhs.startLine, rhs.startLine) - min(lhs.endLine, rhs.endLine)
        guard gap <= 6 else { return false }
        let lhsTitle = stems(lhs.title)
        let rhsTitle = stems(rhs.title)
        guard !lhsTitle.isEmpty, !rhsTitle.isEmpty else { return gap <= 2 && lhs.category == rhs.category }
        let title = overlap(lhsTitle, rhsTitle)
        if gap <= 2 {
            return title >= 0.4 || (lhs.category == rhs.category && lhs.startLine == rhs.startLine)
                || (title >= 0.25 && overlap(stems(lhs.rationale), stems(rhs.rationale)) >= 0.35)
        }
        // A few lines apart (one model at the cause, the other at the effect): clearly the same wording.
        return lhs.category == rhs.category && title >= 0.5
    }

    /// Word stems: words longer than three letters, cut to five letters, so "rounding" / "rounded" and
    /// "Rundung" / "Rundungen" match.
    static func stems(_ text: String) -> Set<Substring> {
        Set(text.lowercased().split(whereSeparator: { !$0.isLetter }).filter { $0.count > 3 }.map { $0.prefix(5) })
    }

    /// Shared stems relative to the shorter text.
    static func overlap(_ lhs: Set<Substring>, _ rhs: Set<Substring>) -> Double {
        guard !lhs.isEmpty, !rhs.isEmpty else { return 0 }
        return Double(lhs.intersection(rhs).count) / Double(min(lhs.count, rhs.count))
    }
}

extension String {
    fileprivate var nilIfEmpty: String? { trimmingCharacters(in: .whitespacesAndNewlines).isEmpty ? nil : self }
}
