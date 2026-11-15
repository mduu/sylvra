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
