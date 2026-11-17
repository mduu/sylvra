import Foundation

/// Block-level Markdown (AI chat answers, pull request descriptions): headings, lists, code, quotes,
/// rules and tables. Inline syntax (bold, code spans, links) stays in the text and is rendered by the view.
public enum MarkdownBlock: Equatable, Sendable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list([MarkdownListItem])
    case code(language: String?, code: String)
    case quote(String)
    case rule
    /// Table rows as written; shown monospaced so the columns line up.
    case table(String)
}

public struct MarkdownListItem: Equatable, Sendable {
    /// "•" for bullets, "3." for numbered items, "☐" / "☑" for task list items.
    public let marker: String
    /// Nesting depth (two spaces or a tab per level).
    public let level: Int
    public var text: String

    public init(marker: String, level: Int, text: String) {
        self.marker = marker
        self.level = level
        self.text = text
    }
}

public enum MarkdownBlocks {
    /// Splits Markdown into blocks. Tolerates streaming: an unclosed fence is a code block so far.
    /// GitHub extras: HTML comments (templates) disappear, HTML-only lines (`<details>`, `<summary>`)
    /// keep their text, and images become links (attachments need a signed-in browser anyway).
    public static func parse(_ text: String) -> [MarkdownBlock] {
        var parser = Parser()
        let normalized = stripHTMLComments(text.replacingOccurrences(of: "\r\n", with: "\n"))
        for line in normalized.components(separatedBy: "\n") {
            parser.consume(line)
        }
        return parser.finish()
    }

    /// Pads the cells so the columns line up in a monospaced font; the separator row becomes dashes.
    public static func alignTable(_ rows: [String]) -> String {
        let cells = rows.map { row in
            row.trimmingCharacters(in: .whitespaces)
                .trimmingCharacters(in: CharacterSet(charactersIn: "|"))
                .components(separatedBy: "|")
                .map { $0.trimmingCharacters(in: .whitespaces) }
        }
        let isSeparator = cells.map { row in row.allSatisfy { !$0.isEmpty && $0.allSatisfy { "-:".contains($0) } } }
        let columns = cells.map(\.count).max() ?? 0
        let widths = (0..<columns).map { column in
            zip(cells, isSeparator).filter { !$1 }.map { $0.0.count > column ? $0.0[column].count : 0 }.max() ?? 0
        }
        return zip(cells, isSeparator).map { row, separator in
            (0..<columns).map { column in
                let cell = row.count > column ? row[column] : ""
                return separator
                    ? String(repeating: "-", count: widths[column])
                    : cell.padding(toLength: widths[column], withPad: " ", startingAt: 0)
            }
            .joined(separator: separator ? "-+-" : " | ")
        }
        .joined(separator: "\n")
    }

    /// `![alt](url)` and `<img src="url">` become `[🖼 alt](url)` links.
    static func imagesAsLinks(_ line: String) -> String {
        var result = line.replacingOccurrences(
            of: #"!\[([^\]]*)\]\(([^)\s]+)[^)]*\)"#, with: "[🖼 $1]($2)", options: .regularExpression)
        result = result.replacingOccurrences(
            of: #"<img\b[^>]*\bsrc="([^"]+)"[^>]*>"#, with: "[🖼 Image]($1)",
            options: [.regularExpression, .caseInsensitive])
        return result.replacingOccurrences(of: "[🖼 ](", with: "[🖼 Image](")
    }

    /// A line made only of HTML tags (`<details>`, `<summary>Title</summary>`, `<br>`) keeps its text.
    static func htmlLineText(_ trimmed: String) -> String? {
        guard trimmed.hasPrefix("<"), trimmed.hasSuffix(">"), !trimmed.hasPrefix("<http") else { return nil }
        let text = trimmed.replacingOccurrences(of: #"<[^>]+>"#, with: "", options: .regularExpression)
            .trimmingCharacters(in: .whitespaces)
        if trimmed.lowercased().hasPrefix("<summary"), !text.isEmpty { return "**\(text)**" }
        return text
    }

    private static func stripHTMLComments(_ text: String) -> String {
        text.replacingOccurrences(of: #"<!--[\s\S]*?(-->|$)"#, with: "", options: .regularExpression)
    }
}

extension MarkdownBlocks {
    fileprivate struct Parser {
        var blocks: [MarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var table: [String] = []
        var items: [MarkdownListItem] = []
        var fence: (language: String?, lines: [String])?

        mutating func consume(_ rawLine: String) {
            let rawTrimmed = rawLine.trimmingCharacters(in: .whitespaces)
            if var open = fence {
                if rawTrimmed.hasPrefix("```") || rawTrimmed.hasPrefix("~~~") {
                    blocks.append(.code(language: open.language, code: open.lines.joined(separator: "\n")))
                    fence = nil
                } else {
                    open.lines.append(rawLine)
                    fence = open
                }
                return
            }
            if rawTrimmed.hasPrefix("```") || rawTrimmed.hasPrefix("~~~") {
                flush()
                let language = rawTrimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                fence = (language.isEmpty ? nil : language, [])
                return
            }
            var line = MarkdownBlocks.imagesAsLinks(rawLine)
            if let text = MarkdownBlocks.htmlLineText(line.trimmingCharacters(in: .whitespaces)) {
                line = text
            }
            consumeText(line)
        }

        private mutating func consumeText(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.isEmpty {
                flush()
            } else if let heading = Self.heading(trimmed) {
                flush()
                blocks.append(heading)
            } else if ["---", "***", "___"].contains(trimmed.replacingOccurrences(of: " ", with: "")) {
                flush()
                blocks.append(.rule)
            } else if trimmed.hasPrefix("|") {
                flush(except: .table)
                table.append(trimmed)
            } else if trimmed.hasPrefix(">") {
                flush(except: .quote)
                quote.append(trimmed.dropFirst().trimmingCharacters(in: .whitespaces))
            } else if let item = Self.listItem(line) {
                flush(except: .list)
                items.append(item)
            } else if !items.isEmpty, line.first == " " || line.first == "\t" {
                // An indented continuation line belongs to the last list item.
                items[items.count - 1].text += "\n" + trimmed
            } else {
                flush(except: .paragraph)
                paragraph.append(line)
            }
        }

        mutating func finish() -> [MarkdownBlock] {
            if let open = fence {
                blocks.append(.code(language: open.language, code: open.lines.joined(separator: "\n")))
                fence = nil
            }
            flush()
            return blocks
        }

        private enum Pending { case paragraph, quote, table, list, none }

        /// Ends the open block unless it is `kind` (consecutive lines of one kind form one block).
        private mutating func flush(except kind: Pending = .none) {
            if kind != .paragraph, !paragraph.isEmpty {
                blocks.append(.paragraph(paragraph.joined(separator: "\n")))
                paragraph = []
            }
            if kind != .quote, !quote.isEmpty {
                blocks.append(.quote(quote.joined(separator: "\n")))
                quote = []
            }
            if kind != .table, !table.isEmpty {
                blocks.append(.table(MarkdownBlocks.alignTable(table)))
                table = []
            }
            if kind != .list, !items.isEmpty {
                blocks.append(.list(items))
                items = []
            }
        }

        private static func heading(_ line: String) -> MarkdownBlock? {
            let hashes = line.prefix { $0 == "#" }.count
            guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
            return .heading(level: hashes, text: line.dropFirst(hashes).trimmingCharacters(in: .whitespaces))
        }

        private static func listItem(_ line: String) -> MarkdownListItem? {
            let indent = line.prefix { $0 == " " || $0 == "\t" }
            let level = indent.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2
            let rest = line.dropFirst(indent.count)
            if let first = rest.first, "-*+".contains(first), rest.dropFirst().first == " " {
                return taskItem(level: level, text: rest.dropFirst(2).trimmingCharacters(in: .whitespaces))
            }
            let digits = rest.prefix { $0.isNumber }
            let afterDigits = rest.dropFirst(digits.count)
            guard !digits.isEmpty, digits.count <= 3, let dot = afterDigits.first, ".)".contains(dot),
                afterDigits.dropFirst().first == " "
            else { return nil }
            return MarkdownListItem(
                marker: "\(digits).", level: level,
                text: afterDigits.dropFirst(2).trimmingCharacters(in: .whitespaces))
        }

        /// `- [ ] todo` / `- [x] done` become ☐ / ☑ items; other bullets keep "•".
        private static func taskItem(level: Int, text: String) -> MarkdownListItem {
            for (box, marker) in [("[ ] ", "☐"), ("[x] ", "☑"), ("[X] ", "☑")] where text.hasPrefix(box) {
                return MarkdownListItem(
                    marker: marker, level: level, text: text.dropFirst(4).trimmingCharacters(in: .whitespaces))
            }
            return MarkdownListItem(marker: "•", level: level, text: text)
        }
    }
}
