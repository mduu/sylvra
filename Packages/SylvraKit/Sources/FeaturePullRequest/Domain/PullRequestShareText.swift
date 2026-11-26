import Foundation
import SylvraCore

/// What goes on the clipboard to ask for a review in a chat: the pull request's link, with its title and one
/// or two sentences about it.
public enum PullRequestShareText {
    static let maxLength = 280

    /// Title, link and description as plain text.
    public static func text(for detail: PullRequestDetail, summary: String? = nil) -> String {
        let description = description(for: detail, summary: summary)
        return [headline(detail), detail.summary.url?.absoluteString, description].compactMap { $0 }
            .filter { !$0.isEmpty }.joined(separator: "\n")
    }

    /// The same as HTML: the title is the link (chat apps such as Teams paste it as one).
    public static func html(for detail: PullRequestDetail, summary: String? = nil) -> String? {
        guard let url = detail.summary.url else { return nil }
        let link = "<a href=\"\(escape(url.absoluteString))\">\(escape(headline(detail)))</a>"
        let description = description(for: detail, summary: summary)
        return description.isEmpty ? link : "\(link)<br>\(escape(description))"
    }

    static func headline(_ detail: PullRequestDetail) -> String {
        "\(detail.summary.title) (\(detail.summary.id.repository) #\(detail.summary.id.number))"
    }

    /// One or two sentences: from `summary` (e.g. the AI summary) when there is one, else from the pull
    /// request's own description.
    static func description(for detail: PullRequestDetail, summary: String?) -> String {
        let source = [summary, detail.body].compactMap { $0 }.map(plain).first { !$0.isEmpty } ?? ""
        return firstSentences(of: source, count: 2)
    }

    /// Markdown as running text: no template comments, headings, code blocks, images or markup characters.
    static func plain(_ markdown: String) -> String {
        var text = markdown.replacing(/<!--[\s\S]*?-->/, with: "")
        text = text.replacing(/```[\s\S]*?```/, with: "")
        text = text.replacing(/!\[[^\]]*\]\([^)]*\)/, with: "")
        text = text.replacing(/\[([^\]]+)\]\([^)]*\)/) { String($0.output.1) }
        let lines = text.split(whereSeparator: \.isNewline).compactMap { line -> String? in
            var line = line.trimmingCharacters(in: .whitespaces)
            // Headings name sections of a template ("## Summary"), not the change.
            if line.hasPrefix("#") || line.hasPrefix("|") || line.hasPrefix("---") { return nil }
            line = line.replacing(/^([-*+]|\d+\.)\s+(\[[ xX]\]\s+)?/, with: "")
            line = line.replacing(/[*_`]/, with: "")
            return line.isEmpty ? nil : line
        }
        // A line without closing punctuation (a list item) still ends its sentence.
        return lines.map { $0.last.map { ".!?:".contains($0) } == true ? $0 : $0 + "." }.joined(separator: " ")
    }

    static func firstSentences(of text: String, count: Int) -> String {
        var sentences: [String] = []
        var rest = Substring(text)
        while sentences.count < count, !rest.isEmpty {
            // A sentence ends at ". " followed by a capital or digit — not inside "e.g. this" or "v1.2".
            if let end = rest.firstMatch(of: /[.!?](?=\s+[\p{Lu}\d])/) {
                sentences.append(String(rest[..<end.range.upperBound]))
                rest = rest[end.range.upperBound...].drop(while: \.isWhitespace)
            } else {
                sentences.append(String(rest))
                rest = ""
            }
        }
        let joined = sentences.joined(separator: " ").trimmingCharacters(in: .whitespaces)
        guard joined.count > maxLength else { return joined }
        return joined.prefix(maxLength - 1).trimmingCharacters(in: .whitespaces) + "…"
    }

    private static func escape(_ text: String) -> String {
        text.replacingOccurrences(of: "&", with: "&amp;").replacingOccurrences(of: "<", with: "&lt;")
            .replacingOccurrences(of: ">", with: "&gt;").replacingOccurrences(of: "\"", with: "&quot;")
    }
}
