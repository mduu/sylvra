import DesignSystem
import SwiftUI
import SylvraCore

/// Sticky header of a file in the diff (pure).
struct DiffFileHeaderView: View {
    let file: FileDiff
    let isViewed: Bool
    let isCollapsed: Bool
    let toggleCollapsed: () -> Void
    let toggleViewed: () -> Void

    var body: some View {
        HStack(spacing: 8) {
            Button(action: toggleCollapsed) {
                Image(systemName: "chevron.right")
                    .rotationEffect(.degrees(isCollapsed ? 0 : 90))
                    .frame(width: 14)
            }
            .buttonStyle(.borderless)
            FileKindIcon(kind: file.kind)
            VStack(alignment: .leading, spacing: 0) {
                Text(file.path).font(.system(size: 12, weight: .medium, design: .monospaced)).lineLimit(1)
                if let previous = file.previousPath {
                    Text("renamed from \(previous)").font(.caption2).foregroundStyle(.secondary)
                }
            }
            if file.status == .added { Badge("new", tint: .green) }
            if file.status == .deleted { Badge("deleted", tint: .red) }
            if file.isBinary { Badge("binary", tint: .secondary) }
            Spacer(minLength: 8)
            Text(verbatim: "+\(file.additions)").foregroundStyle(.green)
            Text(verbatim: "−\(file.deletions)").foregroundStyle(.red)
            Toggle("Viewed", isOn: Binding(get: { isViewed }, set: { _ in toggleViewed() }))
                .toggleStyle(.checkbox)
        }
        .font(.caption.monospacedDigit())
        .padding(.horizontal, 12)
        .padding(.vertical, 7)
        .background(.bar)
        .overlay(alignment: .bottom) { Divider() }
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

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(hunks.enumerated()), id: \.offset) { _, hunk in
                HunkHeaderView(hunk: hunk)
                switch layout {
                case .inline:
                    ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in
                        InlineLineView(line: line, onComment: onComment)
                            .overlay {
                                AIHighlightOverlay(
                                    highlight: line.kind == .removed ? nil : line.newNumber.flatMap(highlight))
                            }
                        inlineAccessories(line)
                    }
                case .sideBySide:
                    ForEach(Array(SideBySideRow.rows(for: hunk).enumerated()), id: \.offset) { _, row in
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
