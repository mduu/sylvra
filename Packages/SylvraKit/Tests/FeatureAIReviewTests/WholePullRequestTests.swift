import Foundation
import Testing

@testable import FeatureAIReview

struct WholePullRequestTests {
    private let opus = AgentSource(provider: "Claude Code", model: "opus", effort: "high")
    private let fable = AgentSource(provider: "Claude Code", model: "fable", effort: "high")

    private func file(_ path: String) -> ReviewableFile {
        ReviewableFile(
            path: path, patch: "@@ -1 +1 @@\n+x", changedNewLines: Set(1...5), visibleNewLines: Set(1...8),
            isNoise: false)
    }

    private func output(overall: String = "[]", patterns: String = "[]") throws -> AgentReviewOutput {
        try JSONDecoder().decode(
            AgentReviewOutput.self,
            from: Data(#"{"summary":"s","findings":[],"overall":\#(overall),"patterns":\#(patterns)}"#.utf8))
    }

    @Test func mergesWholePullRequestPointsOnce() throws {
        let first = try output(
            overall: #"[{"kind":"scattered","title":"Formats live in two places","rationale":"A and B"}]"#)
        let second = try output(
            overall: #"[{"kind":"scattered","title":"formats live in two places","rationale":"again"},"#
                + #"{"kind":"unknown","title":"Too generic"}]"#)
        let result = ReviewMerger.merge([(first, opus), (second, fable)], files: [file("a.swift")])
        #expect(result.overall.map(\.title) == ["Formats live in two places", "Too generic"])
        #expect(result.overall.map(\.kind) == [.scattered, .other])
    }

    @Test func collectsPatternEvidenceFromAllShardsAndOnlyInThePullRequest() throws {
        let first = try output(
            patterns: #"[{"name":"Service layer","verdict":"followed","rationale":"r","#
                + #""evidence":[{"path":"a.swift","startLine":2,"endLine":3},{"path":"gone.swift","startLine":1}]}]"#)
        let second = try output(
            patterns: #"[{"name":"service layer","verdict":"followed","rationale":"r","#
                + #""evidence":[{"path":"b.swift","startLine":4,"endLine":4}]}]"#)
        let result = ReviewMerger.merge([(first, opus), (second, fable)], files: [file("a.swift"), file("b.swift")])
        #expect(result.patterns.count == 1)
        #expect(result.patterns.first?.evidence.map(\.path) == ["a.swift", "b.swift"])
    }

    @Test func cachedResultsWithoutWholePullRequestPointsStillDecode() throws {
        let json = #"{"summary":"s","findings":[],"patterns":[],"history":[]}"#
        #expect(try JSONDecoder().decode(ReviewResult.self, from: Data(json.utf8)).overall.isEmpty)
    }

    @Test func eachShardSeesTheOtherFilesOfThePullRequest() {
        let files = [file("Sources/A.swift"), file("Sources/B.swift"), file("Tests/C.swift")]
        let shard = ShardPlanner.Shard(name: "A", files: [files[0]])
        #expect(ReviewEngine.otherFiles(files, outside: shard) == ["Sources/B.swift (+5)", "Tests/C.swift (+5)"])
    }

    @Test func thePromptAsksForFewCommentsAndTheWholePullRequest() {
        var request = ReviewRequest(
            pullRequestTitle: "T", pullRequestBody: "", shard: ShardPlanner.Shard(name: "A", files: [file("a.swift")]),
            repositoryContext: [], history: [], model: "opus", effort: "high", language: "English",
            workingDirectory: nil)
        request.otherFiles = ["b.swift (+5)"]
        #expect(request.prompt.contains("restate what the code already says"))
        #expect(request.prompt.contains("as a whole"))
        #expect(request.prompt.contains("- b.swift (+5)"))
        #expect(ReviewRequest.outputSchema.contains(#""overall""#))
    }
}
