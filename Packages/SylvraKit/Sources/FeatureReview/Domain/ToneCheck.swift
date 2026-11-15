import Foundation

/// Local, instant check for wording that makes a review comment sound judgmental instead of factual
/// (English and German). Suggestion blocks and inline code are ignored.
public enum ToneCheck {
    public struct Issue: Hashable, Sendable {
        /// The phrase as written in the comment.
        public let phrase: String
        public let reason: Reason
    }

    public enum Reason: Hashable, Sendable {
        /// Implies the point is self-evident ("obviously", "einfach").
        case dismissive
        /// Absolute claims ("always", "nie").
        case absolute
        /// Loaded or emotional words ("stupid", "furchtbar").
        case loaded
        /// Exclamation marks or shouting in capitals.
        case emphasis
    }

    private static let words: [(String, Reason)] =
        [
            "obviously", "clearly", "just", "simply", "of course", "everyone knows", "why would you", "why didn't you",
            "offensichtlich", "natürlich", "einfach", "eigentlich", "selbstverständlich", "wieso hast du",
            "warum hast du",
        ].map { ($0, .dismissive) }
        + ["always", "never", "nobody", "immer", "nie", "niemals", "niemand"].map { ($0, .absolute) }
        + [
            "stupid", "dumb", "terrible", "awful", "horrible", "nonsense", "wrong", "lazy", "mess", "ugly", "hack",
            "dumm", "blöd", "furchtbar", "schrecklich", "unsinn", "quatsch", "falsch", "faul", "murks", "pfusch",
        ].map { ($0, .loaded) }

    private static let shouted = [
        "NOT", "NEVER", "ALWAYS", "MUST", "DON'T", "NO", "PLEASE", "WHY", "NICHT", "NIE", "IMMER", "MUSS", "KEIN",
        "KEINE", "BITTE", "WARUM",
    ]

    /// Issues in reading order, each phrase at most once.
    public static func issues(in text: String) -> [Issue] {
        let prose = proseOnly(text)
        let lower = prose.lowercased()
        var found: [(String.Index, Issue)] = []
        for (word, reason) in words {
            let pattern = "\\b" + NSRegularExpression.escapedPattern(for: word) + "\\b"
            guard let range = lower.range(of: pattern, options: .regularExpression) else { continue }
            found.append((range.lowerBound, Issue(phrase: String(prose[range]), reason: reason)))
        }
        if let range = prose.range(of: "!+", options: .regularExpression) {
            found.append((range.lowerBound, Issue(phrase: String(prose[range]), reason: .emphasis)))
        }
        // Shouting: typical stressed words in capitals (acronyms like CSV or JSON are fine).
        for word in shouted {
            guard let range = prose.range(of: "\\b\(word)\\b", options: .regularExpression) else { continue }
            found.append((range.lowerBound, Issue(phrase: word, reason: .emphasis)))
        }
        return found.sorted { $0.0 < $1.0 }.map(\.1)
    }

    /// The text without fenced code blocks and inline code.
    static func proseOnly(_ text: String) -> String {
        text.replacing(/```[\s\S]*?```/, with: " ").replacing(/`[^`\n]*`/, with: " ")
    }
}
