import FeatureAIReview
import Foundation

/// Progress of a local review as short lines for standard error, meant to be followed by a person or by a coding
/// agent watching the command's output: how many agents finished and how long it has taken, a sign of life while
/// agents run, and a closing line.
///
///     Collecting the changes…
///     Reviewing 12 file(s) against origin/main with opus + fable (effort high)…
///     [0/4 · 0:01] ▸ Core · Opus
///     … 0 of 4 agents done, 4 running · 0:31
///     [1/4 · 1:12] ✓ Core · Opus
///     [4/4 · 2:40] ✓ Combining the models' findings
///     Done in 2:41: 7 findings (2 major, 5 minor), merge risk medium, 380k tokens
@MainActor
final class LocalReviewProgress {
    private let report: @MainActor @Sendable (String) -> Void
    private let started: Date
    private let now: @MainActor () -> Date
    private var states: [String: ReviewEngine.Progress.State] = [:]
    private(set) var failures: [String] = []
    /// Tokens of the finished agents.
    private(set) var tokens: [String: TokenUsage] = [:]
    /// All steps' tokens, combining the findings included.
    var totalTokens: TokenUsage? { TokenUsage.sum(Array(tokens.values)) }

    /// The step that combines several models' findings: not an agent of its own in the counts.
    static let consolidationID = ReviewEngine.consolidationID

    init(report: @escaping @MainActor @Sendable (String) -> Void, now: @escaping @MainActor () -> Date = { .now }) {
        self.report = report
        self.now = now
        started = now()
    }

    private var agents: [ReviewEngine.Progress.State] {
        states.filter { $0.key != Self.consolidationID }.map(\.value)
    }

    var total: Int { agents.count }
    var finished: Int { agents.count { $0 != .queued && $0 != .running } }
    var running: Int { agents.count { $0 == .running } }
    var allFailed: Bool { !agents.isEmpty && failures.count == agents.count }

    /// `1:05` since the review started.
    var elapsed: String { Self.duration(now().timeIntervalSince(started)) }

    func update(_ progress: ReviewEngine.Progress) {
        guard states[progress.id] != progress.state else { return }
        states[progress.id] = progress.state
        if let used = progress.tokens { tokens[progress.id] = used }
        let prefix = "[\(finished)/\(total) · \(elapsed)]"
        switch progress.state {
        case .queued, .skipped: break
        case .running: report("\(prefix) ▸ \(progress.title)")
        case .done: report("\(prefix) ✓ \(progress.title)")
        case .failed(let message):
            failures.append("\(progress.title): \(message)")
            report("\(prefix) ✗ \(progress.title): \(message)")
        }
    }

    /// Sent now and then while agents run, so a long review visibly hasn't stalled.
    func heartbeat() {
        guard running > 0 else { return }
        report("… \(finished) of \(total) agents done, \(running) running · \(elapsed)")
    }

    func finish(_ result: ReviewResult) {
        var line = "Done in \(elapsed): " + Self.outcome(result)
        if let used = totalTokens { line += ", " + used.label }
        report(line)
    }

    /// `7 findings (2 major, 5 minor), merge risk medium`
    static func outcome(_ result: ReviewResult) -> String {
        let findings = result.findings
        var text =
            switch findings.count {
            case 0: "no findings"
            case 1: "1 finding"
            default: "\(findings.count) findings"
            }
        let bySeverity = FindingSeverity.allCases.compactMap { severity -> String? in
            let count = findings.count { $0.severity == severity }
            return count > 0 ? "\(count) \(severity.rawValue)" : nil
        }
        if !bySeverity.isEmpty { text += " (\(bySeverity.joined(separator: ", ")))" }
        if let risk = result.risk { text += ", merge risk \(risk.level.rawValue)" }
        if let mergeability = result.mergeability { text += ", \(mergeability.level.label)" }
        if let slop = result.slop, slop.level != .none { text += ", slop \(slop.level.rawValue)" }
        return text
    }

    static func duration(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        return "\(total / 60):" + String(format: "%02d", total % 60)
    }
}
