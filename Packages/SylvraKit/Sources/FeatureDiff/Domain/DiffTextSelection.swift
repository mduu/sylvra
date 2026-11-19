import SylvraCore

/// Which text a diff row contributes to a selection: the whole line (inline) or one side-by-side half.
public enum DiffSelectionLane: Hashable, Sendable {
    case inline, left, right
}

/// A caret position in a file's diff: hunk, row within the hunk (in the lane's layout) and column.
public struct DiffTextPosition: Hashable, Comparable, Sendable {
    public var hunk: Int
    public var row: Int
    public var column: Int

    public init(hunk: Int, row: Int, column: Int) {
        self.hunk = hunk
        self.row = row
        self.column = column
    }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        (lhs.hunk, lhs.row, lhs.column) < (rhs.hunk, rhs.row, rhs.column)
    }
}

/// Code selected with the mouse across lines, from a column to a column, like in an editor.
///
/// A selection stays in one file and one lane: side by side, the old and the new version are separate texts.
public struct DiffTextSelection: Equatable, Sendable {
    public let path: String
    public let lane: DiffSelectionLane
    /// Where the drag started.
    public var anchor: DiffTextPosition
    /// Where the pointer is.
    public var head: DiffTextPosition

    public init(path: String, lane: DiffSelectionLane, anchor: DiffTextPosition, head: DiffTextPosition) {
        self.path = path
        self.lane = lane
        self.anchor = anchor
        self.head = head
    }

    public var start: DiffTextPosition { min(anchor, head) }
    public var end: DiffTextPosition { max(anchor, head) }
    public var isEmpty: Bool { anchor == head }

    /// The selected columns of a row (`upperBound == Int.max`: to the end of the line), `nil` if not selected.
    public func columns(hunk: Int, row: Int) -> Range<Int>? {
        let start = start
        let end = end
        let position = (hunk, row)
        guard position >= (start.hunk, start.row), position <= (end.hunk, end.row) else { return nil }
        let isFirst = position == (start.hunk, start.row)
        let isLast = position == (end.hunk, end.row)
        let lower = isFirst ? start.column : 0
        let upper = isLast ? end.column : Int.max
        return lower..<max(lower, upper)
    }

    /// The selected lines with their selected text, in order (rows without a line on this side are skipped).
    func selectedLines(in hunks: [Hunk]) -> [(line: DiffLine, text: String)] {
        var result: [(DiffLine, String)] = []
        for hunkIndex in start.hunk...end.hunk where hunks.indices.contains(hunkIndex) {
            let lines = Self.lines(of: hunks[hunkIndex], lane: lane)
            for (row, line) in lines.enumerated() {
                guard let line, let columns = columns(hunk: hunkIndex, row: row) else { continue }
                let characters = Array(line.text)
                let lower = min(columns.lowerBound, characters.count)
                let upper = min(columns.upperBound, characters.count)
                result.append((line, String(characters[lower..<upper])))
            }
        }
        return result
    }

    /// The selected code, lines joined with newlines.
    public func text(in hunks: [Hunk]) -> String {
        selectedLines(in: hunks).map(\.text).joined(separator: "\n")
    }

    /// Where the selected code is: the old version for the left half (and only removed lines inline),
    /// the new version otherwise; `nil` if no selected line has a number on that side.
    public func location(in hunks: [Hunk]) -> CodeLocation? {
        let lines = selectedLines(in: hunks).map(\.line)
        let side: CodeLocation.Side =
            switch lane {
            case .left: .left
            case .right: .right
            case .inline: lines.allSatisfy { $0.kind == .removed } ? .left : .right
            }
        let numbers = lines.compactMap { side == .left ? $0.oldNumber : $0.newNumber }
        guard let first = numbers.first, let last = numbers.last else { return nil }
        return CodeLocation(path: path, line: last, side: side, startLine: first)
    }

    /// A hunk's rows in a lane: the lines inline, one half of each row side by side (`nil`: an empty half).
    static func lines(of hunk: Hunk, lane: DiffSelectionLane) -> [DiffLine?] {
        switch lane {
        case .inline: hunk.lines
        case .left: SideBySideRow.rows(for: hunk).map(\.left)
        case .right: SideBySideRow.rows(for: hunk).map(\.right)
        }
    }
}
