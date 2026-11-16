import AppKit
import DesignSystem
import SwiftUI
import SylvraCore

/// Sticky header of a file in the diff: folder dimmed, file name bold, change bar and a viewed pill (pure).
struct DiffFileHeaderView: View {
    let file: FileDiff
    let isViewed: Bool
    let isCollapsed: Bool
    let toggleCollapsed: () -> Void
    let toggleViewed: () -> Void
    /// Position and reason in the AI reading order.
    var readingStep: (number: Int, step: ReadingStep)?

    var body: some View {
        HStack(spacing: 10) {
            Button(action: toggleCollapsed) {
                Image(systemName: "chevron.right")
                    .font(.system(size: 11, weight: .semibold))
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 14, height: 14)
            }
            .buttonStyle(.borderless)
            FileKindIcon(kind: file.kind)
                .frame(width: 24, height: 24)
                .background(SylvraColor.brandPrimary.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            VStack(alignment: .leading, spacing: 1) {
                HStack(spacing: 0) {
                    if !file.directory.isEmpty {
                        // The folder gives way first; the file name stays readable.
                        Text(file.directory + "/").foregroundStyle(.secondary).truncationMode(.head)
                    }
                    Text(file.fileName).fontWeight(.semibold).layoutPriority(1)
                }
                .font(.system(size: 12.5, design: .monospaced))
                .lineLimit(1)
                if let previous = file.previousPath {
                    Text("renamed from \(previous)").font(.caption2).foregroundStyle(.secondary)
                }
                if let readingStep, !readingStep.step.reason.isEmpty {
                    ReadingReasonView(number: readingStep.number, step: readingStep.step)
                }
            }
            if file.status == .added { Badge("new", tint: SylvraColor.diffAdded) }
            if file.status == .deleted { Badge("deleted", tint: SylvraColor.diffRemoved) }
            if file.isBinary { Badge("binary", tint: .secondary) }
            Spacer(minLength: 8)
            ChangeSummaryView(additions: file.additions, deletions: file.deletions)
            ViewedPill(isViewed: isViewed, toggle: toggleViewed)
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(.regularMaterial)
        .overlay(alignment: .bottom) { Rectangle().fill(SylvraColor.codeHairline).frame(height: 1) }
        .overlay(alignment: .leading) {
            // Accent edge: violet while unreviewed, calm once viewed.
            Rectangle()
                .fill(isViewed ? AnyShapeStyle(Color.secondary.opacity(0.25)) : AnyShapeStyle(AIAccent.border))
                .frame(width: 3)
        }
    }
}

/// `+12 −3` with a five-block bar like GitHub's, in the diff colors (pure).
struct ChangeSummaryView: View {
    let additions: Int
    let deletions: Int

    var body: some View {
        let total = max(additions + deletions, 1)
        let added = Int((Double(additions) / Double(total) * 5).rounded())
        HStack(spacing: 6) {
            Text(verbatim: "+\(additions)").foregroundStyle(SylvraColor.diffAdded)
            Text(verbatim: "−\(deletions)").foregroundStyle(SylvraColor.diffRemoved)
            HStack(spacing: 2) {
                ForEach(0..<5, id: \.self) { index in
                    RoundedRectangle(cornerRadius: 2)
                        .fill(
                            index < added
                                ? SylvraColor.diffAdded
                                : (index < added + (deletions > 0 ? 5 - added : 0)
                                    ? SylvraColor.diffRemoved : Color.secondary.opacity(0.3))
                        )
                        .frame(width: 7, height: 7)
                }
            }
        }
        .font(.system(size: 11.5, weight: .semibold).monospacedDigit())
    }
}

/// Viewed toggle as a pill: "Viewed ✓" (pure).
struct ViewedPill: View {
    let isViewed: Bool
    let toggle: () -> Void

    var body: some View {
        Button(action: toggle) {
            HStack(spacing: 5) {
                Image(systemName: isViewed ? "checkmark.circle.fill" : "circle")
                    .contentTransition(.symbolEffect(.replace))
                Text("Viewed")
            }
            .font(.system(size: 11.5, weight: .medium))
            .padding(.horizontal, 9)
            .padding(.vertical, 4)
            .foregroundStyle(isViewed ? AnyShapeStyle(Color.white) : AnyShapeStyle(.secondary))
            .background(
                isViewed ? AnyShapeStyle(SylvraColor.brandPrimary) : AnyShapeStyle(Color.secondary.opacity(0.12)),
                in: Capsule())
        }
        .buttonStyle(.plain)
        .animation(.snappy, value: isViewed)
        .help(isViewed ? "Mark as not viewed" : "Mark as viewed")
    }
}

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
    @Environment(\.diffSearchQuery) private var searchQuery
    @Environment(\.diffCurrentMatch) private var currentMatch
    @Environment(\.diffIsWide) private var diffIsWide

    /// One lazily built row; unique string IDs (nested offset-based IDs collided and dropped rows).
    private enum Row: Identifiable {
        case header(Int, Hunk)
        case inline(Int, Int, DiffLine, HalfContinuation)
        case sideBySide(Int, Int, SideBySideRow, ConnectorSegment?, Continuation)

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
    }

    /// Rows with their scroll anchors as identity. They are direct children of the diff's lazy stack: a nested
    /// lazy stack hid the IDs of rows not built yet, so jumps to lines further down a file went nowhere.
    private var identifiedRows: [(id: String, row: Row)] {
        var seen = Set<String>()
        return rows.map { row in
            let anchor = row.anchor(path: path)
            return (seen.insert(anchor).inserted ? anchor : "\(path)#\(row.id)", row)
        }
    }

    private var rows: [Row] {
        hunks.enumerated().flatMap { hunkIndex, hunk -> [Row] in
            let lines: [Row] =
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
                            let continuation = Continuation(
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
                case .inline(_, _, let line, let continuation):
                    VStack(spacing: 0) {
                        InlineLineView(line: line, onComment: onComment)
                            .overlay {
                                AIHighlightOverlay(
                                    highlight: line.kind == .removed ? nil : line.newNumber.flatMap(highlight),
                                    line: line.newNumber, gutterWidth: inlineGutterWidth)
                            }
                            .overlay { searchOverlay(texts: [line.text], newLine: line.newNumber) }
                        inlineAccessories(line, continuation: continuation)
                    }
                case .sideBySide(_, _, let row, let connector, let continuation):
                    VStack(spacing: 0) {
                        SideBySideRowView(row: row, connector: connector, onComment: onComment)
                            .overlay {
                                searchOverlay(
                                    texts: [row.left?.text, row.right?.text].compactMap { $0 },
                                    newLine: row.right?.newNumber)
                            }
                            .overlay(alignment: .trailing) {
                                GeometryReader { geometry in
                                    AIHighlightOverlay(
                                        highlight: row.right?.newNumber.flatMap(highlight), line: row.right?.newNumber
                                    )
                                    .frame(width: geometry.size.width / 2)
                                    .frame(maxWidth: .infinity, alignment: .trailing)
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
    private func sideBySideAccessories(_ row: SideBySideRow, continuation: Continuation) -> some View {
        Group {
            if diffIsWide {
                HStack(alignment: .top, spacing: 0) {
                    AccessoryLane(drawsSurface: false) {
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
            HStack(spacing: 0) {
                GutterStrip(continuation: continuation.left)
                RibbonContinuationView(crossSection: continuation.ribbon).frame(width: 44)
                GutterStrip(continuation: continuation.right)
            }
        }
        .background(SylvraColor.codeSurface)
    }

    /// How the row's halves and ribbon continue through its accessories.
    struct Continuation: Hashable {
        let left: HalfContinuation
        let right: HalfContinuation
        let ribbon: ClosedRange<CGFloat>?
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

/// AI reading-order position and reason below a file name (AI accent, pure).
struct ReadingReasonView: View {
    let number: Int
    let step: ReadingStep

    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: "\(number)")
                .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(minWidth: 15, minHeight: 15)
                .background(AIAccent.border, in: Circle())
            if step.isRisky {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(
                    SylvraColor.accentGold)
            }
            Text(step.reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .help("Suggested reading order (AI)")
    }
}
