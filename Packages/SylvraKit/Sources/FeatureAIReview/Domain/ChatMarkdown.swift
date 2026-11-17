import Foundation

/// Block-level Markdown of an AI chat answer: headings, lists, code, quotes, rules and tables.
/// Inline syntax (bold, code spans, links) stays in the text and is rendered by the view.
enum ChatMarkdownBlock: Equatable {
    case heading(level: Int, text: String)
    case paragraph(String)
    case list([ChatListItem])
    case code(language: String?, code: String)
    case quote(String)
    case rule
    /// Table rows as written; shown monospaced so the columns line up.
    case table(String)
}

struct ChatListItem: Equatable {
    /// "•" for bullets, "3." for numbered items.
    let marker: String
    /// Nesting depth (two spaces or a tab per level).
    let level: Int
    var text: String
}

enum ChatMarkdown {
    /// Splits an answer into blocks. Tolerates streaming: an unclosed fence is a code block so far.
    static func parse(_ text: String) -> [ChatMarkdownBlock] {
        var parser = Parser()
        for line in text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n") {
            parser.consume(line)
        }
        return parser.finish()
    }

    /// Pads the cells so the columns line up in a monospaced font; the separator row becomes dashes.
    static func alignTable(_ rows: [String]) -> String {
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

    private struct Parser {
        var blocks: [ChatMarkdownBlock] = []
        var paragraph: [String] = []
        var quote: [String] = []
        var table: [String] = []
        var items: [ChatListItem] = []
        var fence: (language: String?, lines: [String])?

        mutating func consume(_ line: String) {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if var open = fence {
                if trimmed.hasPrefix("```") {
                    blocks.append(.code(language: open.language, code: open.lines.joined(separator: "\n")))
                    fence = nil
                } else {
                    open.lines.append(line)
                    fence = open
                }
                return
            }
            if trimmed.hasPrefix("```") {
                flush()
                let language = trimmed.dropFirst(3).trimmingCharacters(in: .whitespaces)
                fence = (language.isEmpty ? nil : language, [])
            } else if trimmed.isEmpty {
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

        mutating func finish() -> [ChatMarkdownBlock] {
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
                blocks.append(.table(ChatMarkdown.alignTable(table)))
                table = []
            }
            if kind != .list, !items.isEmpty {
                blocks.append(.list(items))
                items = []
            }
        }

        private static func heading(_ line: String) -> ChatMarkdownBlock? {
            let hashes = line.prefix { $0 == "#" }.count
            guard (1...6).contains(hashes), line.dropFirst(hashes).first == " " else { return nil }
            return .heading(level: hashes, text: line.dropFirst(hashes).trimmingCharacters(in: .whitespaces))
        }

        private static func listItem(_ line: String) -> ChatListItem? {
            let indent = line.prefix { $0 == " " || $0 == "\t" }
            let level = indent.reduce(0) { $0 + ($1 == "\t" ? 2 : 1) } / 2
            let rest = line.dropFirst(indent.count)
            if let first = rest.first, "-*+".contains(first), rest.dropFirst().first == " " {
                return ChatListItem(
                    marker: "•", level: level, text: rest.dropFirst(2).trimmingCharacters(in: .whitespaces))
            }
            let digits = rest.prefix { $0.isNumber }
            let afterDigits = rest.dropFirst(digits.count)
            guard !digits.isEmpty, digits.count <= 3, let dot = afterDigits.first, ".)".contains(dot),
                afterDigits.dropFirst().first == " "
            else { return nil }
            return ChatListItem(
                marker: "\(digits).", level: level, text: afterDigits.dropFirst(2).trimmingCharacters(in: .whitespaces))
        }
    }
}
