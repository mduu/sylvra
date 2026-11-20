import Foundation
import SylvraCore
import Testing

@testable import FeatureAIReview

@MainActor
struct ReviewRunTests {
    let id = PullRequestID(owner: "acme", repository: "billing", number: 1234)

    private nonisolated static func file(_ path: String, lines: ClosedRange<Int>) -> ReviewableFile {
        ReviewableFile(
            path: path, patch: "@@ -1 +1 @@\n+x", changedNewLines: Set(lines),
            visibleNewLines: Set(lines.lowerBound - 3...lines.upperBound + 3), isNoise: false)
    }

    /// One review at a time: a running review for another pull request can be replaced by one for this one.
    @Test func replacesAReviewRunningForAnotherPullRequest() async {
        let model = AIReviewModel(
            engine: ReviewEngine(provider: DemoAgentProvider(delay: .milliseconds(300))),
            files: { _ in [Self.file("Sources/Billing/InvoiceService.swift", lines: 8...10)] },
            workspace: { _ in nil },
            defaults: UserDefaults(suiteName: "sylvra-ai-\(UUID().uuidString)")!)
        let other = PullRequestID(owner: "acme", repository: "billing", number: 881)
        let first = Task { await model.run(other, title: "t", body: "") }
        while model.runState != .running { await Task.yield() }
        #expect(model.runningPullRequest == other)
        await model.replaceRunningReview(with: id, title: "t", body: "")
        await first.value
        #expect(model.runningPullRequest == id)
        #expect(model.runState == .done)
        #expect(model.results[id] != nil)
        #expect(model.results[other] == nil)
        #expect(model.finishedAgentCount == model.progress.count)
    }

    /// Regression: while the checkout was prepared, the inspector showed only *Cancel*, no progress.
    @Test func showsWhatTheReviewPreparesBeforeTheAgentsStart() async {
        let gate = CheckoutGate()
        let model = AIReviewModel(
            engine: ReviewEngine(provider: DemoAgentProvider(delay: .zero)),
            files: { _ in [Self.file("Sources/Billing/InvoiceService.swift", lines: 8...10)] },
            workspace: { _ in
                await gate.wait()
                return nil
            },
            defaults: UserDefaults(suiteName: "sylvra-ai-\(UUID().uuidString)")!)
        let run = Task { await model.run(id, title: "t", body: "") }
        while await !gate.isWaiting || model.preparation != String(localized: "Checking out the pull request…") {
            await Task.yield()
        }
        #expect(model.progress.isEmpty)
        await gate.open()
        await run.value
        #expect(model.preparation == nil)
        #expect(model.runState == .done)
    }
}

private actor CheckoutGate {
    private var continuation: CheckedContinuation<Void, Never>?
    var isWaiting: Bool { continuation != nil }
    func wait() async { await withCheckedContinuation { continuation = $0 } }
    func open() {
        continuation?.resume()
        continuation = nil
    }
}
