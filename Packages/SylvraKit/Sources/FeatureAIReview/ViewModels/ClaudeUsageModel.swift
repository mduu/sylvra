import Foundation
import Observation

/// The Claude subscription's limits for the toolbar rings: updated by every review and chat call, and by a tiny
/// probe at launch or on request (see specs/ux.md §9).
@MainActor
@Observable
public final class ClaudeUsageModel {
    public private(set) var usage: ClaudeUsage?
    public private(set) var isRefreshing = false
    /// Why the last probe failed (e.g. Claude Code isn't signed in).
    public private(set) var failure: String?
    /// Asks Claude Code for the limits (`nil`: not available, e.g. in demo mode).
    @ObservationIgnored public var probe: (@Sendable () async throws -> ClaudeUsage?)?

    public init(usage: ClaudeUsage? = nil) {
        self.usage = usage
    }

    public func update(_ newer: ClaudeUsage) {
        usage = usage.map { $0.merging(newer) } ?? newer
        failure = nil
    }

    public func refresh() async {
        guard let probe, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        do {
            if let usage = try await probe() { update(usage) }
        } catch {
            failure = String(describing: error)
        }
    }

    /// Probes only when the values are older than `age` (opening the popover).
    public func refreshIfOlder(than age: TimeInterval = 300, now: Date = .now) async {
        guard usage.map({ now.timeIntervalSince($0.updatedAt) > age }) ?? true else { return }
        await refresh()
    }
}
