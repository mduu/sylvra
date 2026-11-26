import Foundation

/// A job's log as lines worth reading: timestamps shortened to the time, GitHub's group markers turned into
/// headings, and — for a first look — only the part that matters.
public struct JobLog: Equatable, Sendable {
    public struct Line: Equatable, Sendable, Identifiable {
        public enum Kind: Sendable { case plain, heading, error, warning }
        public let id: Int
        /// "14:32:04" (empty when the line has no timestamp).
        public let time: String
        public let text: String
        public let kind: Kind
    }

    public let lines: [Line]
    /// Lines shown before *Show all* (around the first error, else the end).
    public let excerpt: Range<Int>

    /// Lines kept at most (a log of a long job can have tens of thousands).
    static let limit = 3_000
    static let excerptLength = 24

    public init(text: String) {
        var lines: [Line] = []
        for raw in text.split(omittingEmptySubsequences: false, whereSeparator: \.isNewline).suffix(Self.limit) {
            var rest = Substring(raw)
            var time = ""
            // "2026-11-26T14:32:04.0123456Z message"
            if rest.count > 20, rest.dropFirst(4).first == "-", rest.dropFirst(10).first == "T",
                let space = rest.firstIndex(of: " ")
            {
                time = String(rest.dropFirst(11).prefix(8))
                rest = rest[rest.index(after: space)...]
            }
            if rest.hasPrefix("##[endgroup]") { continue }
            let kind: Line.Kind
            if rest.hasPrefix("##[group]") {
                kind = .heading
                rest = rest.dropFirst("##[group]".count)
            } else if rest.hasPrefix("##[error]") {
                kind = .error
                rest = rest.dropFirst("##[error]".count)
            } else if rest.hasPrefix("##[warning]") {
                kind = .warning
                rest = rest.dropFirst("##[warning]".count)
            } else {
                kind = .plain
            }
            lines.append(Line(id: lines.count, time: time, text: String(rest), kind: kind))
        }
        while lines.last?.text.trimmingCharacters(in: .whitespaces).isEmpty == true { lines.removeLast() }
        self.lines = lines
        if let error = lines.firstIndex(where: { $0.kind == .error }) {
            let start = max(0, error - Self.excerptLength + 4)
            excerpt = start..<min(lines.count, start + Self.excerptLength)
        } else {
            excerpt = max(0, lines.count - Self.excerptLength)..<lines.count
        }
    }

    /// Lines outside the excerpt.
    public var hiddenCount: Int { lines.count - excerpt.count }
}
