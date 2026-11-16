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

extension ConnectorSegment {
    /// Horizontal extent of the ribbon (fractions of its width, 0 = left) where this row meets the next one.
    /// Content inserted between the rows (threads, AI findings) continues the ribbon with this cross-section,
    /// so the change block doesn't look split. `nil` when the ribbon ends at this row.
    public func crossSection(rowHeight: CGFloat) -> ClosedRange<CGFloat>? {
        guard indexInBlock < blockRows - 1 else { return nil }
        let boundary = CGFloat(indexInBlock + 1) * rowHeight
        let left = max(CGFloat(leftRows) * rowHeight - 1, 1)
        let right = max(CGFloat(rightRows) * rowHeight - 1, 1)
        if boundary <= min(left, right) { return 0...1 }
        if boundary >= max(left, right) { return nil }
        // The lower edge is a cubic from (1, right) to (0, left) with flat ends; y is monotonic in t.
        func point(_ t: CGFloat) -> (x: CGFloat, y: CGFloat) {
            let u = 1 - t
            let x = u * u * u * 1 + 3 * u * u * t * 0.45 + 3 * u * t * t * 0.55
            let y = u * u * u * right + 3 * u * u * t * right + 3 * u * t * t * left + t * t * t * left
            return (x, y)
        }
        var low: CGFloat = 0
        var high: CGFloat = 1
        for _ in 0..<30 {
            let mid = (low + high) / 2
            let isBeforeCrossing = right > left ? point(mid).y > boundary : point(mid).y < boundary
            if isBeforeCrossing { low = mid } else { high = mid }
        }
        let crossing = point((low + high) / 2).x
        // Inside the band means above the lower edge: towards the taller side.
        return right > left ? crossing...1 : 0...crossing
    }
}

/// How one half of the side-by-side diff continues through content inserted below a row.
public enum HalfContinuation: Hashable, Sendable {
    /// Nothing to continue (context, or the change ends here).
    case none
    /// The change bar of this kind continues (the next row on this half has the same kind).
    case changeBar(DiffLine.Kind)
    /// The half is empty above and below (e.g. a new file): the hatching continues.
    case empty

    public static func between(_ line: DiffLine?, and next: DiffLine?, hasNext: Bool) -> HalfContinuation {
        guard hasNext else { return .none }
        switch (line, next) {
        case (nil, nil): return .empty
        case (let line?, let next?) where line.kind != .context && line.kind == next.kind:
            return .changeBar(line.kind)
        default: return .none
        }
    }
}
