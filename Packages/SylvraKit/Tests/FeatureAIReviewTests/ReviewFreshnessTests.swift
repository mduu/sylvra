import Foundation
import SylvraCore
import Testing

@testable import FeatureAIReview

@MainActor
struct ReviewFreshnessTests {
    let id = PullRequestID(owner: "acme", repository: "billing", number: 1234)

    private func model() -> AIReviewModel {
        AIReviewModel(
            engine: ReviewEngine(provider: DemoAgentProvider(delay: .zero)),
            files: { _ in
                [
                    ReviewableFile(
                        path: "Sources/Billing/InvoiceService.swift", patch: "@@ -1 +1 @@\n+x",
                        changedNewLines: Set(8...10), visibleNewLines: Set(5...13), isNoise: false)
                ]
            },
            workspace: { _ in nil },
            defaults: UserDefaults(suiteName: "sylvra-ai-\(UUID().uuidString)")!)
    }

    @Test func recordsTheReviewedHeadAndNoticesNewCommits() async {
        let model = model()
        var head = "aaa111"
        model.currentHeadSHA = { _ in head }
        await model.run(id, title: "Add invoice export", body: "")
        #expect(model.results[id]?.headSHA == "aaa111")
        #expect(model.results[id]?.reviewedAt != nil)
        #expect(!model.isOutdated(id))
        head = "bbb222"
        #expect(model.isOutdated(id))
        await model.run(id, title: "Add invoice export", body: "")
        #expect(!model.isOutdated(id))
    }

    @Test func unknownHeadsAreNotOutdated() async {
        let model = model()
        #expect(!model.isOutdated(id))
        await model.run(id, title: "Add invoice export", body: "")
        #expect(!model.isOutdated(id))
        #expect(!model.isOutdated(nil))
    }

    @Test func decodesResultsCachedWithoutAHead() throws {
        let json = #"{"summary":"s","findings":[],"patterns":[],"history":[]}"#
        let result = try JSONDecoder().decode(ReviewResult.self, from: Data(json.utf8))
        #expect(result.headSHA == nil)
        #expect(result.reviewedAt == nil)
    }

    @Test func runningAgainClearsTheOldFindingsRightAway() async {
        let model = model()
        await model.run(id, title: "Add invoice export", body: "")
        #expect(!model.visibleFindings(for: id).isEmpty)
        let rerun = Task { await model.run(id, title: "Add invoice export", body: "") }
        await Task.yield()
        #expect(model.results[id] == nil || model.runState == .done)
        await rerun.value
        #expect(model.runState == .done)
        #expect(!model.visibleFindings(for: id).isEmpty)
    }

    @Test func aCancelledRunBringsTheOldFindingsBack() async {
        let slow = AIReviewModel(
            engine: ReviewEngine(provider: DemoAgentProvider(delay: .seconds(5))),
            files: { _ in
                [
                    ReviewableFile(
                        path: "Sources/Billing/InvoiceService.swift", patch: "@@ -1 +1 @@\n+x",
                        changedNewLines: Set(8...10), visibleNewLines: Set(5...13), isNoise: false)
                ]
            },
            workspace: { _ in nil },
            defaults: UserDefaults(suiteName: "sylvra-ai-\(UUID().uuidString)")!)
        let fast = model()
        await fast.run(id, title: "t", body: "")
        let old = fast.results[id]
        #expect(old != nil)
        // Seed the slow model with the finished result, then cancel a new run.
        slow.restoreForTesting(old, for: id)
        let rerun = Task { await slow.run(id, title: "t", body: "") }
        try? await Task.sleep(for: .milliseconds(50))
        #expect(slow.results[id] == nil)
        slow.cancel()
        await rerun.value
        #expect(slow.results[id] == old)
    }
}
