import Foundation
import Platform
import SylvraCore

/// After a review with several models: one more agent call groups findings and whole-PR points that describe
/// the same problem in other words, another language or at another line (the merger's heuristic only catches
/// close wording). Each group becomes one finding with all sources; on any failure the result stays as it is.
public struct FindingConsolidator: Sendable {
    private let provider: any AgentProvider
    private let model: String
    private static let logger = SylvraLog.logger("ai-review")

    public init(provider: any AgentProvider, model: String = "sonnet") {
        self.provider = provider
        self.model = model
    }

    /// Whether a consolidation can change anything.
    public static func isWorthwhile(_ result: ReviewResult) -> Bool {
        result.findings.count > 1 || result.overall.count > 1
    }

    /// The consolidated result; its `tokens` are those of the consolidation call (`nil` when none was made).
    public func consolidate(_ result: ReviewResult, language: String) async -> ReviewResult {
        guard Self.isWorthwhile(result) else { return result }
        do {
            let reply = try await provider.chat(
                ChatRequest(
                    message: Self.prompt(for: result), sessionID: nil, model: model, effort: "low",
                    language: language, workingDirectory: nil))
            guard let groups = Self.groups(in: reply.text) else {
                Self.logger.error("Consolidating findings: no groups in the answer")
                var unchanged = result
                unchanged.tokens = reply.tokens
                return unchanged
            }
            var consolidated = Self.apply(groups, to: result)
            consolidated.tokens = reply.tokens
            return consolidated
        } catch {
            Self.logger.error("Consolidating findings failed: \(String(describing: error), privacy: .public)")
            return result
        }
    }

    // MARK: Prompt and answer

    struct Groups: Decodable, Equatable {
        var findings: [[Int]]?
        var overall: [[Int]]?
    }

    static func prompt(for result: ReviewResult) -> String {
        let findings = result.findings.enumerated().map { index, finding in
            "[\(index)] \(finding.path):\(finding.startLine)-\(finding.endLine) · \(finding.category) · "
                + "\(finding.title) — \(finding.rationale.prefix(300))"
        }
        let overall = result.overall.enumerated().map { index, point in
            "[\(index)] \(point.kind.rawValue) · \(point.title) — \(point.rationale.prefix(300))"
        }
        return """
            Several AI models reviewed the same pull request independently. Below are their merged findings. \
            Group the entries that describe the same underlying problem (the same root cause and the same fix), \
            even when worded differently, written in different languages or placed a few lines apart. Entries \
            about different problems stay separate, even on the same line. When unsure, do not group.

            Reply with JSON only, no prose and no code fence, in this form:
            {"findings": [[0, 3]], "overall": [[1, 2]]}
            List only groups with two or more entries; use [] when nothing belongs together.

            Findings:
            \(findings.isEmpty ? "(none)" : findings.joined(separator: "\n"))

            Whole-pull-request points:
            \(overall.isEmpty ? "(none)" : overall.joined(separator: "\n"))
            """
    }

    /// The JSON object in the answer (also inside a code fence or after a sentence).
    static func groups(in text: String) -> Groups? {
        guard let start = text.firstIndex(of: "{"), let end = text.lastIndex(of: "}"), start < end else { return nil }
        return try? JSONDecoder().decode(Groups.self, from: Data(text[start...end].utf8))
    }

    // MARK: Applying groups

    /// Merges each valid group: findings only within one file (a merged finding has one place in the diff),
    /// every index at most once; invalid indices are ignored.
    static func apply(_ groups: Groups, to result: ReviewResult) -> ReviewResult {
        var merged = result
        merged.findings = mergeFindings(result.findings, groups: groups.findings ?? [])
        merged.overall = mergeOverall(result.overall, groups: groups.overall ?? [])
        return merged
    }

    private static func mergeFindings(_ findings: [ReviewFinding], groups: [[Int]]) -> [ReviewFinding] {
        var used = Set<Int>()
        var replacements: [Int: ReviewFinding] = [:]
        for group in validGroups(groups, count: findings.count, used: &used) {
            let members = group.map { findings[$0] }
            guard Set(members.map(\.path)).count == 1 else {
                used.subtract(group)
                continue
            }
            // The most severe wording leads; the others add their sources and higher ratings.
            guard let leadIndex = group.min(by: { findings[$0].severity.rank < findings[$1].severity.rank }) else {
                continue
            }
            var lead = findings[leadIndex]
            for member in members {
                for source in member.sources where !lead.sources.contains(source) { lead.sources.append(source) }
                lead.impact = [lead.impact, member.impact].compactMap { $0 }.max()
                lead.likelihood = [lead.likelihood, member.likelihood].compactMap { $0 }.max()
            }
            replacements[leadIndex] = lead
        }
        return findings.indices.compactMap { index in
            if let replacement = replacements[index] { return replacement }
            return used.contains(index) ? nil : findings[index]
        }
    }

    private static func mergeOverall(_ points: [OverallFinding], groups: [[Int]]) -> [OverallFinding] {
        var used = Set<Int>()
        let firsts = Set(validGroups(groups, count: points.count, used: &used).compactMap(\.first))
        return points.indices.compactMap { index in
            firsts.contains(index) || !used.contains(index) ? points[index] : nil
        }
    }

    /// Sorted groups of two or more existing, not yet used indices.
    private static func validGroups(_ groups: [[Int]], count: Int, used: inout Set<Int>) -> [[Int]] {
        groups.compactMap { group in
            let members = Array(Set(group)).filter { (0..<count).contains($0) && !used.contains($0) }.sorted()
            guard members.count > 1 else { return nil }
            used.formUnion(members)
            return members
        }
    }
}
