import Foundation
import SylvraCore
import Testing

@testable import FeatureAIReview

/// After several models: an agent groups what describes the same problem; Sylvra merges only valid groups.
struct FindingConsolidatorTests {
    private let opus = AgentSource(provider: "Claude Code", model: "opus", effort: "high")
    private let fable = AgentSource(provider: "Claude Code", model: "fable", effort: "high")

    private func finding(
        _ title: String, path: String = "a.swift", line: Int, severity: FindingSeverity = .minor,
        source: AgentSource, impact: RiskLevel? = nil
    ) -> ReviewFinding {
        ReviewFinding(
            path: path, startLine: line, endLine: line, severity: severity, category: "bug", title: title,
            rationale: "r", suggestion: nil, confidence: 0.8, impact: impact, likelihood: nil, sources: [source],
            isAnchored: true)
    }

    private func result(_ findings: [ReviewFinding], overall: [OverallFinding] = []) -> ReviewResult {
        var result = ReviewResult(
            summary: "s", findings: findings, patterns: [], history: [], readingOrder: [], risk: nil)
        result.overall = overall
        return result
    }

    @Test func readsGroupsAlsoInsideACodeFence() {
        let text = "Here you go:\n```json\n{\"findings\": [[0, 2]], \"overall\": []}\n```"
        #expect(FindingConsolidator.groups(in: text) == .init(findings: [[0, 2]], overall: []))
        #expect(FindingConsolidator.groups(in: "No duplicates.") == nil)
    }

    @Test func mergesAGroupIntoItsMostSevereFindingWithAllSources() {
        let input = result([
            finding("Totals drift", line: 8, source: opus, impact: .low),
            finding("Unrelated", line: 30, source: opus),
            finding("Gerundete Summen weichen ab", line: 14, severity: .major, source: fable, impact: .high),
        ])
        let merged = FindingConsolidator.apply(.init(findings: [[0, 2]]), to: input)
        #expect(merged.findings.map(\.title) == ["Unrelated", "Gerundete Summen weichen ab"])
        let lead = merged.findings.last
        #expect(lead?.sources == [fable, opus])
        #expect(lead?.impact == .high)
    }

    @Test func ignoresGroupsAcrossFilesAndInvalidIndices() {
        let input = result([
            finding("A", line: 1, source: opus), finding("B", path: "b.swift", line: 1, source: fable),
            finding("C", line: 2, source: fable),
        ])
        let merged = FindingConsolidator.apply(.init(findings: [[0, 1], [7, 2], [2, 2]]), to: input)
        #expect(merged.findings.map(\.title) == ["A", "B", "C"])
    }

    @Test func mergesWholePullRequestPoints() {
        let input = result(
            [],
            overall: [
                OverallFinding(kind: .scattered, title: "Formats in two places", rationale: "r"),
                OverallFinding(kind: .simpler, title: "Could be one function", rationale: "r"),
                OverallFinding(kind: .scattered, title: "Format logic is split up", rationale: "r"),
            ])
        let merged = FindingConsolidator.apply(.init(overall: [[0, 2]]), to: input)
        #expect(merged.overall.map(\.title) == ["Formats in two places", "Could be one function"])
    }

    @Test func keepsTheResultWhenTheAgentFails() async {
        let input = result([finding("A", line: 1, source: opus), finding("B", line: 9, source: fable)])
        let consolidated = await FindingConsolidator(provider: GroupingProvider(answer: nil))
            .consolidate(input, language: "English")
        #expect(consolidated.findings.map(\.title) == ["A", "B"])
    }

    @Test func theEngineCombinesFindingsOfSeveralModels() async {
        let provider = GroupingProvider(answer: #"{"findings": [[0, 1]], "overall": []}"#)
        var settings = ReviewSettings(models: ["opus", "fable"])
        settings.maxParallelAgents = 1
        let file = ReviewableFile(
            path: "a.swift", patch: "@@ -1 +1 @@\n+x", changedNewLines: [10], visibleNewLines: Set(5...15),
            isNoise: false)
        let input = ReviewEngine.Input(
            files: [file], title: "t", body: "", context: [], history: [], settings: settings, workingDirectory: nil)
        let result = await ReviewEngine(provider: provider).run(input) { _ in }
        #expect(result.findings.count == 1)
        #expect(Set(result.findings.first?.sources.map(\.model) ?? []) == ["opus", "fable"])
        #expect(await provider.chats == 1)
    }
}

/// Each model reports the rounding problem in its own words; the chat answers with `answer`.
private actor GroupingProvider: AgentProvider {
    nonisolated let name = "Claude Code"
    let answer: String?
    private(set) var chats = 0

    init(answer: String?) { self.answer = answer }

    nonisolated func detectVersion() async -> String? { "test" }

    func chat(_ request: ChatRequest) async throws -> ChatReply {
        chats += 1
        guard let answer else { throw AgentError.failed("offline") }
        return ChatReply(text: answer, sessionID: nil)
    }

    nonisolated func review(_ request: ReviewRequest) async throws -> AgentReviewOutput {
        let title = request.model == "opus" ? "Totals drift because items are rounded" : "Rundung pro Position"
        let line = request.model == "opus" ? 8 : 14
        let json = """
            {"summary":"s","findings":[{"path":"a.swift","startLine":\(line),"endLine":\(line),"severity":"major",\
            "category":"bug","title":"\(title)","rationale":"r","confidence":0.8}],"patterns":[]}
            """
        return try JSONDecoder().decode(AgentReviewOutput.self, from: Data(json.utf8))
    }
}
