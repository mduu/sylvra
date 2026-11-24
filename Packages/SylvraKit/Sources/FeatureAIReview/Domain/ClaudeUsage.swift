import Foundation

/// How much of the Claude subscription's limits is used: the 5-hour window, the week across all models and the
/// week for Fable. Read from the `rate_limit_event` Claude Code prints with `--output-format stream-json` (no
/// credentials needed).
public struct ClaudeUsage: Equatable, Sendable {
    /// One limit window.
    public struct Window: Equatable, Sendable {
        /// Share used, 0…1.
        public var utilization: Double
        public var resetsAt: Date?
        /// The limit is reached (Claude Code refuses further requests until the reset).
        public var isBlocked: Bool

        public init(utilization: Double, resetsAt: Date?, isBlocked: Bool = false) {
            self.utilization = utilization
            self.resetsAt = resetsAt
            self.isBlocked = isBlocked
        }

        /// Share left, 0…1; a window past its reset is full again.
        public func remaining(at now: Date = .now) -> Double {
            if let resetsAt, now >= resetsAt { return 1 }
            return isBlocked ? 0 : min(max(1 - utilization, 0), 1)
        }
    }

    public enum Level: Equatable, Sendable {
        case plenty
        /// 20 % or less left.
        case low
        /// Less than 10 % left.
        case critical

        public init(remaining: Double) {
            self = remaining < 0.10 ? .critical : remaining <= 0.20 ? .low : .plenty
        }
    }

    public var fiveHour: Window?
    public var week: Window?
    /// Fable's own weekly limit (`seven_day_overage_included`); only reported after Fable was used.
    public var fable: Window?
    public var updatedAt: Date

    public init(fiveHour: Window? = nil, week: Window? = nil, fable: Window? = nil, updatedAt: Date = .now) {
        self.fiveHour = fiveHour
        self.week = week
        self.fable = fable
        self.updatedAt = updatedAt
    }

    public var isEmpty: Bool { fiveHour == nil && week == nil && fable == nil }

    /// The most worrying level of all windows.
    public func level(at now: Date = .now) -> Level {
        let remaining = [fiveHour, week, fable].compactMap { $0?.remaining(at: now) }
        return Level(remaining: remaining.min() ?? 1)
    }

    /// Newer values win; a window the newer report doesn't mention (Fable after a Haiku call) is kept until it
    /// resets.
    public func merging(_ newer: ClaudeUsage) -> ClaudeUsage {
        func keep(_ old: Window?) -> Window? {
            guard let old, let reset = old.resetsAt, reset > newer.updatedAt else { return nil }
            return old
        }
        return ClaudeUsage(
            fiveHour: newer.fiveHour ?? keep(fiveHour), week: newer.week ?? keep(week),
            fable: newer.fable ?? keep(fable), updatedAt: newer.updatedAt)
    }

    /// The last `rate_limit_event` in Claude Code's stream-json output (`nil`: none).
    public static func parse(streamJSON output: String, at now: Date = .now) -> ClaudeUsage? {
        let events = output.split(whereSeparator: \.isNewline).filter { $0.contains("\"rate_limit_event\"") }
        for line in events.reversed() {
            guard let event = try? JSONDecoder().decode(Event.self, from: Data(line.utf8)),
                event.type == "rate_limit_event", let windows = event.rateLimitInfo?.unifiedWindows
            else { continue }
            let usage = ClaudeUsage(
                fiveHour: windows["five_hour"]?.window, week: windows["seven_day"]?.window,
                fable: windows["seven_day_overage_included"]?.window, updatedAt: now)
            if !usage.isEmpty { return usage }
        }
        return nil
    }

    private struct Event: Decodable {
        struct Info: Decodable {
            let unifiedWindows: [String: RawWindow]?
        }
        struct RawWindow: Decodable {
            let utilization: Double?
            let resetsAt: Double?
            let status: String?

            var window: Window? {
                guard let utilization else { return nil }
                return Window(
                    utilization: utilization, resetsAt: resetsAt.map(Date.init(timeIntervalSince1970:)),
                    isBlocked: status.map { $0 != "allowed" && $0 != "allowed_warning" } ?? false)
            }
        }
        let type: String
        let rateLimitInfo: Info?

        enum CodingKeys: String, CodingKey {
            case type
            case rateLimitInfo = "rate_limit_info"
        }
    }
}

extension ClaudeUsage {
    /// Fixture for demo mode and screenshots.
    public static var demo: ClaudeUsage {
        let now = Date.now
        return ClaudeUsage(
            fiveHour: Window(utilization: 0.41, resetsAt: now.addingTimeInterval(5_400)),
            week: Window(utilization: 0.18, resetsAt: now.addingTimeInterval(4 * 86_400)),
            fable: Window(utilization: 0.83, resetsAt: now.addingTimeInterval(4 * 86_400)), updatedAt: now)
    }
}
