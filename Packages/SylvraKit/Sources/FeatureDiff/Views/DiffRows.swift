import SwiftUI

/// One lazily built row of a file's diff; unique string IDs (nested offset-based IDs collided and dropped rows).
enum DiffRow: Identifiable {
    case header(Int, Hunk)
    case inline(Int, Int, DiffLine, HalfContinuation)
    case sideBySide(Int, Int, SideBySideRow, ConnectorSegment?, DiffRowContinuation)

    var id: String {
        switch self {
        case .header(let hunk, _): "h\(hunk)"
        case .inline(let hunk, let index, _, _): "i\(hunk)-\(index)"
        case .sideBySide(let hunk, let index, _, _, _): "s\(hunk)-\(index)"
        }
    }

    /// Scroll anchor: new-side lines use `DiffScreenModel.lineAnchor`, so jumps can target them.
    func anchor(path: String) -> String {
        switch self {
        case .header(let hunk, _): "\(path)#hunk\(hunk)"
        case .inline(_, _, let line, _):
            line.kind == .removed || line.newNumber == nil
                ? "\(path)#old\(line.oldNumber ?? 0)"
                : DiffScreenModel.lineAnchor(path: path, line: line.newNumber ?? 0)
        case .sideBySide(_, _, let row, _, _):
            row.right?.newNumber.map { DiffScreenModel.lineAnchor(path: path, line: $0) }
                ?? "\(path)#old\(row.left?.oldNumber ?? 0)"
        }
    }

    /// Rows with their scroll anchors as identity.
    static func identifiedRows(path: String, hunks: [Hunk], layout: DiffScreenModel.Layout)
        -> [(id: String, row: DiffRow)]
    {
        var seen = Set<String>()
        return rows(hunks: hunks, layout: layout).map { row in
            let anchor = row.anchor(path: path)
            return (seen.insert(anchor).inserted ? anchor : "\(path)#\(row.id)", row)
        }
    }

    static func rows(hunks: [Hunk], layout: DiffScreenModel.Layout) -> [DiffRow] {
        hunks.enumerated().flatMap { hunkIndex, hunk -> [DiffRow] in
            let lines: [DiffRow] =
                switch layout {
                case .inline:
                    hunk.lines.enumerated().map { index, line in
                        let next = hunk.lines.indices.contains(index + 1) ? hunk.lines[index + 1] : nil
                        return .inline(hunkIndex, index, line, .between(line, and: next, hasNext: next != nil))
                    }
                case .sideBySide:
                    {
                        let rows = SideBySideRow.rows(for: hunk)
                        let segments = ConnectorSegment.segments(for: rows)
                        return rows.indices.map { index in
                            let next = rows.indices.contains(index + 1) ? rows[index + 1] : nil
                            let continuation = DiffRowContinuation(
                                left: .between(rows[index].left, and: next?.left, hasNext: next != nil),
                                right: .between(rows[index].right, and: next?.right, hasNext: next != nil),
                                ribbon: segments[index]?.crossSection(rowHeight: diffRowHeight))
                            return .sideBySide(hunkIndex, index, rows[index], segments[index], continuation)
                        }
                    }()
                }
            return [.header(hunkIndex, hunk)] + lines
        }
    }
}

/// How a side-by-side row's halves and ribbon continue through its accessories.
struct DiffRowContinuation: Hashable {
    let left: HalfContinuation
    let right: HalfContinuation
    let ribbon: ClosedRange<CGFloat>?
}

/// The rows of each file, built once per hunks and layout. A file body is re-evaluated whenever the diff
/// screen is (new closures every time); rebuilding the rows of a 10k-line file each time made the UI stutter.
/// Unchanged hunks compare by their storage first, so a hit costs next to nothing.
@MainActor
final class DiffRowCache {
    private struct Entry {
        let hunks: [Hunk]
        let layout: DiffScreenModel.Layout
        let rows: [(id: String, row: DiffRow)]
    }

    private var entries: [String: Entry] = [:]

    func rows(path: String, hunks: [Hunk], layout: DiffScreenModel.Layout) -> [(id: String, row: DiffRow)] {
        if let entry = entries[path], entry.layout == layout, entry.hunks == hunks { return entry.rows }
        let rows = DiffRow.identifiedRows(path: path, hunks: hunks, layout: layout)
        entries[path] = Entry(hunks: hunks, layout: layout, rows: rows)
        return rows
    }

    func removeAll() { entries = [:] }
}

extension EnvironmentValues {
    /// Set by `DiffScreen`; previews build the rows directly.
    @Entry var diffRowCache: DiffRowCache?
}
