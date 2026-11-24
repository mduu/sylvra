import Foundation
import Platform
import Testing

@testable import FeatureAIReview

/// The subscription's limits come from the `rate_limit_event` in Claude Code's stream-json output.
struct ClaudeUsageTests {
    static let output = """
        {"type":"system","subtype":"init","session_id":"s"}
        {"type":"rate_limit_event","rate_limit_info":{"status":"allowed","resetsAt":1795518000,"rateLimitType":"five_hour","unifiedWindows":{"five_hour":{"utilization":0.41,"resetsAt":1795518000,"status":"allowed"},"seven_day":{"utilization":0.18,"resetsAt":1796029200,"status":"allowed"},"seven_day_overage_included":{"utilization":0.24,"resetsAt":1796029200,"status":"allowed"}}},"session_id":"s"}
        {"type":"assistant","message":{"content":[{"type":"text","text":"ok"}]}}
        {"type":"result","subtype":"success","result":"ok","session_id":"s"}
        """

    @Test func readsTheWindowsFromStreamJSON() throws {
        let now = Date(timeIntervalSince1970: 1_795_510_000)
        let usage = try #require(ClaudeUsage.parse(streamJSON: Self.output, at: now))
        #expect(usage.fiveHour?.utilization == 0.41)
        #expect(usage.fiveHour?.resetsAt == Date(timeIntervalSince1970: 1_795_518_000))
        #expect(usage.week?.utilization == 0.18)
        #expect(usage.fable?.utilization == 0.24)
        #expect(abs((usage.fiveHour?.remaining(at: now) ?? 0) - 0.59) < 0.0001)
        #expect(ClaudeUsage.parse(streamJSON: #"{"type":"result","result":"ok"}"#) == nil)
    }

    @Test func levelsTurnOrangeAtTwentyAndRedBelowTen() {
        #expect(ClaudeUsage.Level(remaining: 0.21) == .plenty)
        #expect(ClaudeUsage.Level(remaining: 0.20) == .low)
        #expect(ClaudeUsage.Level(remaining: 0.10) == .low)
        #expect(ClaudeUsage.Level(remaining: 0.09) == .critical)
    }

    @Test func aWindowPastItsResetIsFullAgain() {
        let reset = Date(timeIntervalSince1970: 1000)
        let window = ClaudeUsage.Window(utilization: 0.95, resetsAt: reset)
        #expect(window.remaining(at: reset.addingTimeInterval(-1)) < 0.06)
        #expect(window.remaining(at: reset) == 1)
        #expect(ClaudeUsage.Window(utilization: 0.5, resetsAt: nil, isBlocked: true).remaining() == 0)
    }

    @Test func keepsFableUntilItResetsWhenALaterCallDoesNotReportIt() {
        let now = Date(timeIntervalSince1970: 1000)
        let fable = ClaudeUsage.Window(utilization: 0.24, resetsAt: now.addingTimeInterval(500))
        let earlier = ClaudeUsage(fable: fable, updatedAt: now)
        let later = ClaudeUsage(fiveHour: .init(utilization: 0.5, resetsAt: nil), updatedAt: now.addingTimeInterval(10))
        #expect(earlier.merging(later).fable == fable)
        #expect(earlier.merging(later).fiveHour?.utilization == 0.5)
        let afterReset = ClaudeUsage(updatedAt: now.addingTimeInterval(600))
        #expect(earlier.merging(afterReset).fable == nil)
    }

    @Test func providerUsesTheResultLineAndReportsTheLimits() throws {
        #expect(ClaudeCodeProvider.resultLine(of: Self.output).contains("\"subtype\":\"success\""))
        #expect(ClaudeCodeProvider.resultLine(of: "Not logged in") == "Not logged in")
        #expect(ClaudeCodeProvider.probeArguments.contains("haiku"))
        #expect(ClaudeCodeProvider.probeArguments.contains("stream-json"))
    }

    @MainActor @Test func modelMergesReportsAndProbes() async {
        let model = ClaudeUsageModel()
        model.probe = { ClaudeUsage.parse(streamJSON: ClaudeUsageTests.output) }
        await model.refreshIfOlder(than: 300)
        #expect(model.usage?.week?.utilization == 0.18)
        model.update(ClaudeUsage(week: .init(utilization: 0.3, resetsAt: nil)))
        #expect(model.usage?.week?.utilization == 0.3)
        #expect(model.usage?.fable?.utilization == 0.24)
    }
}
