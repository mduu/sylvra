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
