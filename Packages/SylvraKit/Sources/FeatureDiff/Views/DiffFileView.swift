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

    /// One lazily built row; unique string IDs (nested offset-based IDs collided and dropped rows).
    private enum Row: Identifiable {
        case header(Int, Hunk)
        case inline(Int, Int, DiffLine)
        case sideBySide(Int, Int, SideBySideRow)

        var id: String {
            switch self {
            case .header(let hunk, _): "h\(hunk)"
            case .inline(let hunk, let index, _): "i\(hunk)-\(index)"
            case .sideBySide(let hunk, let index, _): "s\(hunk)-\(index)"
            }
        }
    }

    private var rows: [Row] {
        hunks.enumerated().flatMap { hunkIndex, hunk -> [Row] in
            let lines: [Row] =
                switch layout {
                case .inline: hunk.lines.enumerated().map { .inline(hunkIndex, $0, $1) }
                case .sideBySide: SideBySideRow.rows(for: hunk).enumerated().map { .sideBySide(hunkIndex, $0, $1) }
                }
            return [.header(hunkIndex, hunk)] + lines
        }
    }

    var body: some View {
        LazyVStack(spacing: 0) {  // lazy: only visible lines are built, even for 10k-line files
            ForEach(rows) { row in
                switch row {
                case .header(_, let hunk):
                    HunkHeaderView(hunk: hunk)
                case .inline(_, _, let line):
                    VStack(spacing: 0) {
                        InlineLineView(line: line, onComment: onComment)
                            .overlay {
                                AIHighlightOverlay(
                                    highlight: line.kind == .removed ? nil : line.newNumber.flatMap(highlight))
                            }
                        inlineAccessories(line)
                    }
                case .sideBySide(_, _, let row):
                    VStack(spacing: 0) {
                        SideBySideRowView(row: row, onComment: onComment)
                            .overlay(alignment: .trailing) {
                                GeometryReader { geometry in
                                    AIHighlightOverlay(highlight: row.right?.newNumber.flatMap(highlight))
                                        .frame(width: geometry.size.width / 2)
                                        .frame(maxWidth: .infinity, alignment: .trailing)
                                }
                            }
                        sideBySideAccessories(row)
                    }
                }
            }
        }
        .environment(\.syntaxLanguage, SyntaxHighlighter.Language(path: path))
    }

    /// Context lines can carry threads on both sides; removed lines on the left, added lines on the right.
    @ViewBuilder private func inlineAccessories(_ line: DiffLine) -> some View {
        if line.kind != .added, let old = line.oldNumber {
            accessory(CodeLocation(path: path, line: old, side: .left))
        }
        if line.kind != .removed, let new = line.newNumber {
            accessory(CodeLocation(path: path, line: new, side: .right))
        }
    }

    /// Accessories span the full width below the row (left side first): thread cards stay readable
    /// in narrow windows.
    @ViewBuilder private func sideBySideAccessories(_ row: SideBySideRow) -> some View {
        if let old = row.left?.oldNumber { accessory(CodeLocation(path: path, line: old, side: .left)) }
        if let new = row.right?.newNumber { accessory(CodeLocation(path: path, line: new, side: .right)) }
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

/// Xcode-style AI highlight: a soft gradient fading to the right, a gold edge and ✦ for the selected finding (pure).
struct AIHighlightOverlay: View {
    let highlight: LineHighlight?

    var body: some View {
        if let highlight {
            ZStack(alignment: .leading) {
                AIAccent.lineGradient(opacity: highlight.isSelected ? 0.45 : 0.18 + 0.22 * highlight.intensity)
                Rectangle()
                    .fill(highlight.isSelected ? AnyShapeStyle(SylvraColor.accentGold) : AnyShapeStyle(AIAccent.border))
                    .frame(width: 3)
            }
            .overlay(alignment: .trailing) {
                if highlight.isSelected {
                    Image(systemName: "sparkle")
                        .font(.system(size: 9, weight: .bold))
                        .foregroundStyle(SylvraColor.accentGold)
                        .padding(.trailing, 6)
                        .opacity(highlight.isSelected ? 1 : 0.7)
                }
            }
            .allowsHitTesting(false)
            .transition(.opacity)
        }
    }
}
