import Foundation

/// A row of the side-by-side layout: old line on the left, new line on the right.
public struct SideBySideRow: Hashable, Sendable {
    public let left: DiffLine?
    public let right: DiffLine?

    /// Context lines appear on both sides; runs of removed/added lines are paired top to bottom.
    public static func rows(for hunk: Hunk) -> [SideBySideRow] {
        var rows: [SideBySideRow] = []
        var removed: [DiffLine] = []
        var added: [DiffLine] = []

        func flush() {
            for index in 0..<max(removed.count, added.count) {
                rows.append(
                    SideBySideRow(
                        left: index < removed.count ? removed[index] : nil,
                        right: index < added.count ? added[index] : nil))
            }
            removed.removeAll()
            added.removeAll()
        }

        for line in hunk.lines {
            switch line.kind {
            case .removed:
                if !added.isEmpty { flush() }
                removed.append(line)
            case .added:
                added.append(line)
            case .context:
                flush()
                rows.append(SideBySideRow(left: line, right: line))
            }
        }
        flush()
        return rows
    }
}

/// The part of a change block's connector ribbon that falls on one side-by-side row.
public struct ConnectorSegment: Hashable, Sendable {
    /// Row index inside the change block.
    public let indexInBlock: Int
    /// Rows of the block.
    public let blockRows: Int
    /// Removed lines on the left (they start at the block's first row).
    public let leftRows: Int
    /// Added lines on the right (they start at the block's first row).
    public let rightRows: Int

    /// One segment per row; `nil` for unchanged rows.
    public static func segments(for rows: [SideBySideRow]) -> [ConnectorSegment?] {
        func isChange(_ row: SideBySideRow) -> Bool { row.left?.kind == .removed || row.right?.kind == .added }
        var result = [ConnectorSegment?](repeating: nil, count: rows.count)
        var start = 0
        while start < rows.count {
            guard isChange(rows[start]) else {
                start += 1
                continue
            }
            var end = start
            while end < rows.count, isChange(rows[end]) { end += 1 }
            let block = rows[start..<end]
            let left = block.count { $0.left?.kind == .removed }
            let right = block.count { $0.right?.kind == .added }
            for index in start..<end {
                result[index] = ConnectorSegment(
                    indexInBlock: index - start, blockRows: end - start, leftRows: left, rightRows: right)
            }
            start = end
        }
        return result
    }
}
