import AppKit
import DesignSystem
import SwiftUI
import SylvraCore

/// The hunks of a file in the chosen layout (pure).
/// `accessory` renders extra content (e.g. review threads) below a line; it is empty for most lines.
struct DiffFileBodyView<Accessory: View>: View {
    let path: String
    let hunks: [Hunk]
    let layout: DiffScreenModel.Layout
    let accessory: (CodeLocation) -> Accessory
    var highlight: (Int) -> LineHighlight? = { _ in nil }
    var onComment: CommentRequest?
    /// Unchanged lines hidden above each hunk, and how to reveal them (`nil`: all).
    var hiddenAbove: [Int] = []
    var expand: ((_ hunk: Int, _ count: Int?) -> Void)?
    /// Puts copied code on the clipboard (right-click menu of a line).
    var copy: (String) -> Void = { DiffCopy.toClipboard($0) }
    @Environment(\.diffSearchQuery) private var searchQuery
    @Environment(\.diffCurrentMatch) private var currentMatch
    @Environment(\.diffIsWide) private var diffIsWide
    @Environment(\.diffSelectFinding) private var selectFinding
    @Environment(\.diffOpenInIDE) var ide
    @Environment(\.diffRowCache) private var rowCache

    /// Rows with their scroll anchors as identity. They are direct children of the diff's lazy stack: a nested
    /// lazy stack hid the IDs of rows not built yet, so jumps to lines further down a file went nowhere.
    private var identifiedRows: [(id: String, row: DiffRow)] {
        rowCache?.rows(path: path, hunks: hunks, layout: layout)
            ?? DiffRow.identifiedRows(path: path, hunks: hunks, layout: layout)
    }

    var body: some View {
        // No own stack: the rows are built lazily by the diff's LazyVStack, even for 10k-line files.
        ForEach(identifiedRows, id: \.id) { entry in
            Group {
                switch entry.row {
                case .header(let index, let hunk):
                    HunkHeaderView(
                        hunk: hunk,
                        hiddenLines: hiddenAbove.indices.contains(index) ? hiddenAbove[index] : 0,
                        expand: expand.map { expand in { count in expand(index, count) } })
                case .inline(let hunkIndex, let rowIndex, let line, let continuation):
                    VStack(spacing: 0) {
                        InlineLineView(
                            line: line, onComment: onComment, openInIDE: ideAction(line, in: hunks[hunkIndex]),
                            selectionKey: .init(path: path, lane: .inline, hunk: hunkIndex, row: rowIndex)
                        )
                        .selectsFinding(
                            line.kind == .removed ? nil : line.newNumber.flatMap(highlight)?.findingID,
                            using: selectFinding
                        )
                        .contextMenu {
                            DiffCopyMenu(
                                newLine: line.kind == .removed ? nil : line,
                                oldLine: line.kind == .removed ? line : nil, hunk: hunks[hunkIndex], copy: copy,
                                openInIDE: ideAction(line, in: hunks[hunkIndex]))
                        }
                        .overlay {
                            AIHighlightOverlay(
                                highlight: line.kind == .removed ? nil : line.newNumber.flatMap(highlight),
                                line: line.newNumber, gutterWidth: inlineGutterWidth)
                        }
                        .overlay { searchOverlay(texts: [line.text], newLine: line.newNumber) }
                        inlineAccessories(line, continuation: continuation)
                    }
                case .sideBySide(let hunkIndex, let rowIndex, let row, let connector, let continuation):
                    VStack(spacing: 0) {
                        SideBySideRowView(
                            row: row, connector: connector, onComment: onComment,
                            openInIDE: { ideAction($0 == .left ? row.left : row.right, in: hunks[hunkIndex]) },
                            selectionPlace: .init(path: path, hunk: hunkIndex, row: rowIndex)
                        )
                        .selectsFinding(row.right?.newNumber.flatMap(highlight)?.findingID, using: selectFinding)
                        .contextMenu {
                            DiffCopyMenu(
                                newLine: row.right, oldLine: row.left, hunk: hunks[hunkIndex], copy: copy,
                                openInIDE: ideAction(row.right ?? row.left, in: hunks[hunkIndex]))
                        }
                        .overlay {
                            searchOverlay(
                                texts: [row.left?.text, row.right?.text].compactMap { $0 },
                                newLine: row.right?.newNumber)
                        }
                        .overlay(alignment: .trailing) {
                            // Only on highlighted rows: a geometry reader on every row re-ran per resize frame.
                            if let lineHighlight = row.right?.newNumber.flatMap(highlight) {
                                GeometryReader { geometry in
                                    AIHighlightOverlay(highlight: lineHighlight, line: row.right?.newNumber)
                                        .frame(width: max((geometry.size.width - connectorWidth) / 2, 0))
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                            }
                        }
                        sideBySideAccessories(row, continuation: continuation)
                    }
                }
            }
            .id(entry.id)
        }
        .environment(\.syntaxLanguage, SyntaxHighlighter.Language(path: path))
    }

    /// Find in diff: matching rows get a gold tint, the current match a stronger edge.
    @ViewBuilder
    private func searchOverlay(texts: [String], newLine: Int?) -> some View {
        if searchQuery.count >= 2,
            texts.contains(where: { $0.range(of: searchQuery, options: .caseInsensitive) != nil })
        {
            let isCurrent = newLine.map { DiffScreenModel.lineAnchor(path: path, line: $0) } == currentMatch
            Rectangle()
                .fill(SylvraColor.accentGold.opacity(isCurrent ? 0.28 : 0.14))
                .overlay(alignment: .leading) {
                    if isCurrent { Rectangle().fill(SylvraColor.accentGold).frame(width: 3) }
                }
                .allowsHitTesting(false)
        }
    }

    /// Context lines can carry threads on both sides; removed lines on the left, added lines on the right.
    /// Accessories are indented past the gutter, which keeps running underneath (the diff stays one surface).
    @ViewBuilder private func inlineAccessories(_ line: DiffLine, continuation: HalfContinuation) -> some View {
        if line.kind != .added, let old = line.oldNumber {
            AccessoryLane(gutterWidth: inlineGutterWidth, continuation: continuation) {
                accessory(CodeLocation(path: path, line: old, side: .left))
            }
        }
        if line.kind != .removed, let new = line.newNumber {
            AccessoryLane(gutterWidth: inlineGutterWidth, continuation: continuation) {
                accessory(CodeLocation(path: path, line: new, side: .right))
            }
        }
    }

    /// Side by side: a thread sits under the half it belongs to; the other half and the center keep going.
    /// All surfaces are backgrounds, so lines without threads add no height at all.
    /// Wide diffs put a thread under its own half; narrow diffs (all columns visible) use one lane across the
    /// code width, so cards never get squeezed into half a column.
    @ViewBuilder
    private func sideBySideAccessories(_ row: SideBySideRow, continuation: DiffRowContinuation) -> some View {
        Group {
            if diffIsWide {
                HStack(alignment: .top, spacing: 0) {
                    AccessoryLane(drawsSurface: false, reachesTrailingEdge: false) {
                        if let old = row.left?.oldNumber { accessory(CodeLocation(path: path, line: old, side: .left)) }
                    }
                    Spacer(minLength: 44).frame(width: 44)
                    AccessoryLane(drawsSurface: false) {
                        if let new = row.right?.newNumber {
                            accessory(CodeLocation(path: path, line: new, side: .right))
                        }
                    }
                }
            } else {
                AccessoryLane(drawsSurface: false) {
                    if let old = row.left?.oldNumber { accessory(CodeLocation(path: path, line: old, side: .left)) }
                    if let new = row.right?.newNumber { accessory(CodeLocation(path: path, line: new, side: .right)) }
                }
            }
        }
        .background {
            // The change block keeps going underneath: ribbon, change bars and hatching continue, so the
            // inserted card doesn't read as a divider between the code above and below.
            // Clipped: an empty lane must not spill into the line above (see `AccessoryLane`).
            Color.clear.overlay {
                HStack(spacing: 0) {
                    GutterStrip(continuation: continuation.left)
                    RibbonContinuationView(crossSection: continuation.ribbon).frame(width: 44)
                    GutterStrip(continuation: continuation.right)
                }
            }
            .clipped()
        }
        .background(SylvraColor.codeSurface)
    }

}

struct FileKindIcon: View {
    let kind: FileKind

    var body: some View {
        Image(systemName: symbol)
            .foregroundStyle(.secondary)
            .frame(width: 14)
            .help(kind.rawValue.capitalized)
    }

    private var symbol: String {
        switch kind {
        case .source: "chevron.left.forwardslash.chevron.right"
        case .test: "checkmark.diamond"
        case .config: "gearshape"
        case .generated: "gearshape.2"
        case .lockfile: "lock"
        case .asset: "photo"
        case .docs: "doc.text"
        }
    }
}

struct Badge: View {
    let title: LocalizedStringKey
    let tint: Color

    init(_ title: LocalizedStringKey, tint: Color) {
        self.title = title
        self.tint = tint
    }

    var body: some View {
        Text(title)
            .font(.caption2.weight(.semibold))
            .foregroundStyle(tint)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(tint.opacity(0.12), in: Capsule())
    }
}
