import Foundation

/// Builds GitHub ```` ```suggestion ```` blocks for review comments.
public enum SuggestionBlock {
    /// A suggestion block pre-filled with the given code (the selected lines).
    public static func make(code: String) -> String {
        "```suggestion\n\(code)\n```"
    }

    /// Inserts a suggestion block at the end of `body`, separated by a blank line when needed.
    /// Returns the new body.
    public static func insert(code: String, into body: String) -> String {
        let block = make(code: code)
        let trimmed = body.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? block + "\n" : trimmed + "\n\n" + block + "\n"
    }

    /// A comment body from a rationale and proposed code. GitHub offers "Commit suggestion" for every
    /// ```` ```suggestion ```` block, so the code becomes one only when it reads as a 1:1 replacement of the
    /// `original` lines; any other code (a sketch, prose, code for elsewhere) stays a plain code block.
    public static func commentBody(rationale: String, code: String?, replacing original: String) -> String {
        guard let code, !code.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return rationale }
        let block = isReplacement(code, for: original) ? make(code: code) : "```\n\(code)\n```"
        let trimmed = rationale.trimmingCharacters(in: .whitespacesAndNewlines)
        return trimmed.isEmpty ? block : trimmed + "\n\n" + block
    }

    /// Whether `code` can replace the `original` lines as they are: the lines are known, the code has no
    /// placeholders, is not prose and resembles them (same indentation or shared identifiers).
    public static func isReplacement(_ code: String, for original: String) -> Bool {
        let codeLines = nonEmptyLines(code)
        let originalLines = nonEmptyLines(original)
        guard !codeLines.isEmpty, !originalLines.isEmpty else { return false }
        guard !codeLines.contains(where: isPlaceholder), !codeLines.allSatisfy(isProse) else { return false }
        if indentation(codeLines[0]) == indentation(originalLines[0]) { return true }
        let originalTokens = identifiers(original)
        guard !originalTokens.isEmpty else { return false }
        return Double(originalTokens.intersection(identifiers(code)).count) / Double(originalTokens.count) >= 0.34
    }

    private static func nonEmptyLines(_ text: String) -> [Substring] {
        text.split(separator: "\n").filter { !$0.allSatisfy(\.isWhitespace) }
    }

    private static func indentation(_ line: Substring) -> Substring { line.prefix { $0 == " " || $0 == "\t" } }

    /// `...`, `…` or a comment standing in for code that was left out.
    private static func isPlaceholder(_ line: Substring) -> Bool {
        let trimmed = line.trimmingCharacters(in: .whitespaces)
        let stripped = trimmed.drop { "/#*-<!".contains($0) }.trimmingCharacters(in: .whitespaces)
        return stripped.hasPrefix("...") || stripped.hasPrefix("…") || trimmed.hasSuffix("...")
            || trimmed.hasSuffix("…")
    }

    /// A sentence: several words and none of the punctuation code is made of.
    private static func isProse(_ line: Substring) -> Bool {
        let words = line.split(separator: " ").count
        return words >= 4 && !line.contains(where: { "(){}[]=;<>\"`'|&$".contains($0) })
    }

    private static func identifiers(_ text: String) -> Set<String> {
        Set(text.matches(of: /[A-Za-z_][A-Za-z0-9_]{2,}/).map { String($0.output) })
    }
}

/// A coarse split of Markdown comment bodies into prose and fenced code blocks, enough to render
/// suggestions and code distinctly. Inline Markdown in prose is rendered by `AttributedString`.
public enum MarkdownBlock: Hashable, Sendable {
    case text(String)
    /// A fenced code block; `language` is the info string (`suggestion` for code suggestions).
    case code(language: String, code: String)

    public static func parse(_ markdown: String) -> [MarkdownBlock] {
        var blocks: [MarkdownBlock] = []
        var prose: [Substring] = []
        var code: [Substring] = []
        var fence: (marker: String, language: String)?

        func flushProse() {
            let text = prose.joined(separator: "\n").trimmingCharacters(in: .newlines)
            if !text.trimmingCharacters(in: .whitespaces).isEmpty { blocks.append(.text(text)) }
            prose.removeAll()
        }

        let normalized = markdown.replacingOccurrences(of: "\r\n", with: "\n")
        for line in normalized.split(separator: "\n", omittingEmptySubsequences: false) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if let open = fence {
                if trimmed == open.marker {
                    blocks.append(.code(language: open.language, code: code.joined(separator: "\n")))
                    code.removeAll()
                    fence = nil
                } else {
                    code.append(line)
                }
            } else if trimmed.hasPrefix("```") || trimmed.hasPrefix("~~~") {
                flushProse()
                let marker = String(trimmed.prefix { $0 == trimmed.first })
                fence = (marker, trimmed.dropFirst(marker.count).trimmingCharacters(in: .whitespaces))
            } else {
                prose.append(line)
            }
        }
        if let open = fence {
            // Unterminated fence: keep the code (GitHub renders it until the end of the body).
            blocks.append(.code(language: open.language, code: code.joined(separator: "\n")))
        }
        flushProse()
        return blocks
    }
}
