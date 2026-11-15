import Foundation

/// A stable line identity in a pull request diff, shared between slices (diff, review, AI findings).
///
/// Mirrors GitHub's review comment addressing: `line` (and optional `startLine` for ranges) on a diff `side`.
public struct CodeLocation: Hashable, Sendable, CustomStringConvertible {
    /// Side of the diff: `left` is the base (old) version, `right` the head (new) version.
    public enum Side: String, Hashable, Sendable {
        case left = "LEFT"
        case right = "RIGHT"
    }

    public let path: String
    /// Last line of the location (the line a comment is anchored to).
    public let line: Int
    public let side: Side
    /// First line for multi-line ranges; `nil` for single lines.
    public let startLine: Int?

    public init(path: String, line: Int, side: Side, startLine: Int? = nil) {
        self.path = path
        self.line = line
        self.side = side
        self.startLine = startLine.flatMap { $0 < line ? $0 : nil }
    }

    /// All lines covered by the location.
    public var lines: ClosedRange<Int> { (startLine ?? line)...line }

    /// The single-line location a range is anchored to (where threads are shown).
    public var anchor: CodeLocation { CodeLocation(path: path, line: line, side: side) }

    public var description: String {
        let range = startLine.map { "\($0)–\(line)" } ?? "\(line)"
        return "\(path):\(range)"
    }
}
