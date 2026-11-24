import Foundation

/// Tokens an agent call used, as Claude Code reports them in its result (`usage`).
public struct TokenUsage: Hashable, Sendable, Codable {
    public var input: Int
    public var cacheCreation: Int
    public var cacheRead: Int
    public var output: Int

    public init(input: Int = 0, cacheCreation: Int = 0, cacheRead: Int = 0, output: Int = 0) {
        self.input = input
        self.cacheCreation = cacheCreation
        self.cacheRead = cacheRead
        self.output = output
    }

    enum CodingKeys: String, CodingKey {
        case input = "input_tokens"
        case cacheCreation = "cache_creation_input_tokens"
        case cacheRead = "cache_read_input_tokens"
        case output = "output_tokens"
    }

    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        input = try container.decodeIfPresent(Int.self, forKey: .input) ?? 0
        cacheCreation = try container.decodeIfPresent(Int.self, forKey: .cacheCreation) ?? 0
        cacheRead = try container.decodeIfPresent(Int.self, forKey: .cacheRead) ?? 0
        output = try container.decodeIfPresent(Int.self, forKey: .output) ?? 0
    }

    /// Everything the model read and wrote, cached input included.
    public var total: Int { input + cacheCreation + cacheRead + output }

    public static func + (lhs: TokenUsage, rhs: TokenUsage) -> TokenUsage {
        TokenUsage(
            input: lhs.input + rhs.input, cacheCreation: lhs.cacheCreation + rhs.cacheCreation,
            cacheRead: lhs.cacheRead + rhs.cacheRead, output: lhs.output + rhs.output)
    }

    /// The sum of the known usages (`nil` when none is known).
    public static func sum(_ usages: [TokenUsage?]) -> TokenUsage? {
        let known = usages.compactMap { $0 }
        return known.isEmpty ? nil : known.reduce(TokenUsage(), +)
    }

    /// `850`, `120k`, `2.4M`
    public static func abbreviated(_ count: Int) -> String {
        switch count {
        case ..<1_000: "\(count)"
        case ..<1_000_000: "\(Int((Double(count) / 1_000).rounded()))k"
        default: String(format: "%.1fM", Double(count) / 1_000_000)
        }
    }

    /// `120k tokens`
    public var label: String { String(localized: "\(Self.abbreviated(total)) tokens") }

    /// `98k read from the cache · 18k new · 4k written`
    public var breakdown: String {
        let (cached, new, written) = (
            Self.abbreviated(cacheRead), Self.abbreviated(input + cacheCreation), Self.abbreviated(output)
        )
        return String(localized: "\(cached) read from the cache · \(new) new input · \(written) output")
    }
}

/// Elapsed time as `0:42`, `2:41` or `1:05:12`.
public enum ElapsedTime {
    public static func format(_ seconds: TimeInterval) -> String {
        let total = max(Int(seconds.rounded(.down)), 0)
        let (hours, minutes, rest) = (total / 3600, total / 60 % 60, total % 60)
        return hours > 0
            ? String(format: "%d:%02d:%02d", hours, minutes, rest) : String(format: "%d:%02d", minutes, rest)
    }
}
