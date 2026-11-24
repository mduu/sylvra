import Foundation
import Platform
import SylvraCore
import Testing

@testable import FeatureAIReview

/// How long a review took and how many tokens it used.
struct ReviewCostTests {
    @Test func readsTheTokensFromTheResult() throws {
        let stdout = #"""
            {"type":"result","result":"x","structured_output":{"summary":"ok","findings":[]},"usage":{"input_tokens":12,"cache_creation_input_tokens":3000,"cache_read_input_tokens":115000,"output_tokens":2400}}
            """#
        let output = try ClaudeCodeProvider.decode(
            ProcessResult(exitCode: 0, standardOutput: stdout, standardError: ""))
        let tokens = try #require(output.tokens)
        #expect(tokens.total == 120_412)
        #expect(tokens.label == "120k tokens")
        #expect(tokens.breakdown == "115k read from the cache · 3k new input · 2k output")
    }

    @Test func abbreviatesTokenCounts() {
        #expect(TokenUsage.abbreviated(850) == "850")
        #expect(TokenUsage.abbreviated(120_400) == "120k")
        #expect(TokenUsage.abbreviated(2_430_000) == "2.4M")
        #expect(TokenUsage.sum([nil, TokenUsage(output: 5), TokenUsage(input: 7)])?.total == 12)
        #expect(TokenUsage.sum([nil]) == nil)
    }

    @Test func formatsElapsedTime() {
        #expect(ElapsedTime.format(42.9) == "0:42")
        #expect(ElapsedTime.format(161) == "2:41")
        #expect(ElapsedTime.format(3912) == "1:05:12")
    }

    @MainActor @Test func aFinishedReviewKeepsItsDurationAndStepTimes() async {
        let model = AIReviewModel(
            engine: ReviewEngine(provider: DemoAgentProvider(delay: .milliseconds(20))),
            files: { _ in
                [
                    ReviewableFile(
                        path: "Sources/A.swift", patch: "@@ -1 +1 @@\n+x", changedNewLines: [1],
                        visibleNewLines: [1], isNoise: false)
                ]
            },
            workspace: { _ in nil },
            defaults: UserDefaults(suiteName: "sylvra-cost-\(UUID().uuidString)")!)
        let id = PullRequestID(owner: "acme", repository: "billing", number: 1)
        await model.run(id, title: "t", body: "")
        #expect((model.results[id]?.duration ?? 0) > 0)
        let step = model.progress.first.flatMap { model.stepTimes[$0.id] }
        #expect(step?.start != nil && step?.end != nil)
    }

    @Test func oldResultsDecodeWithoutDurationAndTokens() throws {
        let json = #"{"summary":"s","findings":[],"patterns":[],"history":[]}"#
        let result = try JSONDecoder().decode(ReviewResult.self, from: Data(json.utf8))
        #expect(result.duration == nil && result.tokens == nil)
    }
}
