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
        /// Absolute claims about a person ("you always", "du vergisst nie"); "nobody" / "niemand" anywhere.
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
        + ["nobody", "niemand"].map { ($0, .absolute) }
        + [
            "stupid", "dumb", "terrible", "awful", "horrible", "nonsense", "wrong", "lazy", "mess", "ugly", "hack",
            "dumm", "blöd", "furchtbar", "schrecklich", "unsinn", "quatsch", "falsch", "faul", "murks", "pfusch",
        ].map { ($0, .loaded) }

    /// Absolute only when said about a person: "the test always returns true" describes the program.
    private static let absoluteAdverbs = ["always", "never", "immer", "nie", "niemals"]

    /// Words that address the author; a sentence with one of them is about a person, not the code.
    private static let addressing: Set<String> = [
        "you", "your", "yours", "you're", "you've", "du", "dich", "dir", "dein", "deine", "deinen", "deinem",
        "deiner", "deines", "euch", "euer", "eure", "euren", "eurem",
    ]

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
        if let issue = absoluteAboutAPerson(in: prose) { found.append(issue) }
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

    /// The first "always" / "never" (and German forms) in a sentence that addresses the author.
    private static func absoluteAboutAPerson(in prose: String) -> (String.Index, Issue)? {
        let pattern = "\\b(" + absoluteAdverbs.joined(separator: "|") + ")\\b"
        // Substrings share the text's indices, so a sentence's range is one in the whole text.
        for sentence in prose.split(whereSeparator: { ".!?\n".contains($0) }) {
            let words = sentence.lowercased().split(whereSeparator: { !$0.isLetter && $0 != "'" })
            guard words.contains(where: { addressing.contains(String($0)) }),
                let range = sentence.range(of: pattern, options: [.regularExpression, .caseInsensitive])
            else { continue }
            return (range.lowerBound, Issue(phrase: String(sentence[range]), reason: .absolute))
        }
        return nil
    }

    /// The text without fenced code blocks and inline code.
    static func proseOnly(_ text: String) -> String {
        text.replacing(/```[\s\S]*?```/, with: " ").replacing(/`[^`\n]*`/, with: " ")
    }
}
