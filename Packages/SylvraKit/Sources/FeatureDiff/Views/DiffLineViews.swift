import AppKit
import DesignSystem
import SwiftUI
import SylvraCore

private let diffRowHeight: CGFloat = 22
private let codeFont = Font.system(size: 12.5, design: .monospaced)
/// Unchanged code is slightly dimmed, so the change is in the light (focus lens, see specs/ux.md §7.2).
private let contextOpacity = 0.62
private let connectorWidth: CGFloat = 44

/// Request to start a comment on a line: side, line number and whether to extend the current range (⇧-click).
typealias CommentRequest = (_ side: CodeLocation.Side, _ line: Int, _ extendsRange: Bool) -> Void

/// One line in the inline (unified) layout (pure).
struct InlineLineView: View {
    @Environment(\.syntaxLanguage) private var language
    let line: DiffLine
    var onComment: CommentRequest?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                CommentGutter(isHovered: isHovered, action: commentAction)
                LineNumber(line.oldNumber, kind: line.kind)
                LineNumber(line.newNumber, kind: line.kind)
            }
            .background(SylvraColor.codeGutter)
            .commentOnClick(commentAction)
            HStack(spacing: 0) {
                ChangeBar(kind: line.kind)
                Text(marker)
                    .frame(width: 18)
                    .foregroundStyle(DiffColors.accent(line.kind) ?? .secondary)
                    .fontWeight(.semibold)
                Text(line.attributedText(language: language))
                    .lineLimit(1)
                    .opacity(line.kind == .context ? contextOpacity : 1)
                    .frame(maxWidth: .infinity, alignment: .leading)
            }
            .frame(maxHeight: .infinity)
            .background(DiffColors.background(line.kind))
        }
        .font(codeFont)
        .frame(height: diffRowHeight)
        .background(SylvraColor.codeSurface)
        .onHover { isHovered = $0 }
    }

    private var commentAction: ((Bool) -> Void)? {
        guard let onComment, let number else { return nil }
        return { onComment(side, number, $0) }
    }

    /// Removed lines are commented on the base side, everything else on the head side.
    private var side: CodeLocation.Side { line.kind == .removed ? .left : .right }
    private var number: Int? { line.kind == .removed ? line.oldNumber : line.newNumber }

    private var marker: String {
        switch line.kind {
        case .added: "+"
        case .removed: "−"
        case .context: ""
        }
    }
}

/// One row in the side-by-side layout (pure).
struct SideBySideRowView: View {
    let row: SideBySideRow
    var connector: ConnectorSegment?
    var onComment: CommentRequest?

    var body: some View {
        HStack(spacing: 0) {
            SideBySideHalf(line: row.left, number: row.left?.oldNumber, side: .left, onComment: onComment)
            ConnectorRibbonView(segment: connector, rowHeight: diffRowHeight).frame(width: connectorWidth)
            SideBySideHalf(line: row.right, number: row.right?.newNumber, side: .right, onComment: onComment)
        }
        .font(codeFont)
        .frame(height: diffRowHeight)
    }
}

private struct SideBySideHalf: View {
    @Environment(\.syntaxLanguage) private var language
    let line: DiffLine?
    let number: Int?
    let side: CodeLocation.Side
    let onComment: CommentRequest?
    @State private var isHovered = false

    var body: some View {
        HStack(spacing: 0) {
            HStack(spacing: 0) {
                CommentGutter(isHovered: isHovered && line != nil, action: commentAction)
                LineNumber(number, kind: line?.kind ?? .context)
            }
            .background(SylvraColor.codeGutter)
            .commentOnClick(commentAction)
            if let line {
                HStack(spacing: 0) {
                    ChangeBar(kind: line.kind)
                    Text(line.attributedText(language: language))
                        .lineLimit(1)
                        .opacity(line.kind == .context ? contextOpacity : 1)
                        .padding(.leading, 8)
                        .frame(maxWidth: .infinity, alignment: .leading)
                }
                .frame(maxHeight: .infinity)
                .background(DiffColors.background(line.kind))
            } else {
                HatchPattern().frame(maxWidth: .infinity)
            }
        }
        .frame(maxWidth: .infinity)
        .background(SylvraColor.codeSurface)
        .onHover { isHovered = $0 }
    }

    private var commentAction: ((Bool) -> Void)? {
        guard let onComment, let number, line != nil else { return nil }
        return { onComment(side, number, $0) }
    }
}

/// `+` button shown in the gutter while the line is hovered. ⇧-click extends the comment to a range.
private struct CommentGutter: View {
    let isHovered: Bool
    let action: ((_ extendsRange: Bool) -> Void)?

    var body: some View {
        ZStack {
            if let action, isHovered {
                Button {
                    action(NSEvent.modifierFlags.contains(.shift))
                } label: {
                    Image(systemName: "plus")
                        .font(.system(size: 10, weight: .bold))
                        .foregroundStyle(.white)
                        .frame(width: 16, height: 16)
                        .background(SylvraColor.brandPrimary, in: RoundedRectangle(cornerRadius: 4))
                }
                .buttonStyle(.plain)
                .help("Comment on this line (⇧-click to extend a range)")
                .transition(.scale(scale: 0.6).combined(with: .opacity))
            }
        }
        .frame(width: 20)
        .animation(.snappy(duration: 0.12), value: isHovered)
    }
}

extension View {
    /// Clicking a line number starts a comment, like the gutter `+` button.
    fileprivate func commentOnClick(_ action: ((Bool) -> Void)?) -> some View {
        contentShape(Rectangle())
            .onTapGesture { action?(NSEvent.modifierFlags.contains(.shift)) }
    }
}

/// Hunk separator: a hairline with a capsule naming the enclosing scope and line range (pure).
struct HunkHeaderView: View {
    let hunk: Hunk

    var body: some View {
        HStack(spacing: 10) {
            hairline.frame(width: 24)
            HStack(spacing: 6) {
                Image(systemName: "ellipsis")
                    .font(.system(size: 10, weight: .bold))
                    .foregroundStyle(SylvraColor.brandPrimary)
                if !hunk.section.isEmpty {
                    Text(hunk.section)
                        .font(.system(size: 11.5, weight: .medium, design: .monospaced))
                        .foregroundStyle(.primary.opacity(0.8))
                        .lineLimit(1)
                }
                Text(verbatim: "lines \(hunk.newStart)–\(hunk.newStart + max(hunk.newCount - 1, 0))")
                    .font(.system(size: 10.5).monospacedDigit())
                    .foregroundStyle(.secondary)
            }
            .padding(.horizontal, 10)
            .padding(.vertical, 3)
            .background(SylvraColor.brandPrimary.opacity(0.10), in: Capsule())
            .overlay(Capsule().strokeBorder(SylvraColor.brandPrimary.opacity(0.22)))
            hairline
        }
        .padding(.horizontal, 10)
        .frame(maxWidth: .infinity, minHeight: 34)
        .background(SylvraColor.codeSurface)
    }

    private var hairline: some View {
        Rectangle().fill(SylvraColor.codeHairline).frame(height: 1)
    }
}

/// The slice of a change block's ribbon on this row: a curved band from the removed lines (left, coral)
/// to the added lines (right, green). Each row draws the whole block shape shifted by its index and clipped,
/// so the slices join into one continuous ribbon (pure, see specs/ux.md §7.2).
struct ConnectorRibbonView: View {
    let segment: ConnectorSegment?
    let rowHeight: CGFloat

    var body: some View {
        Canvas { context, size in
            // Hairline through unchanged rows keeps the two halves visually apart.
            context.fill(
                Path(CGRect(x: size.width / 2 - 0.5, y: 0, width: 1, height: size.height)),
                with: .color(SylvraColor.codeHairline))
            guard let segment else { return }
            context.translateBy(x: 0, y: -CGFloat(segment.indexInBlock) * rowHeight)
            let left = CGFloat(max(segment.leftRows, 0)) * rowHeight
            let right = CGFloat(max(segment.rightRows, 0)) * rowHeight
            let width = size.width
            var band = Path()
            band.move(to: CGPoint(x: 0, y: 1))
            band.addLine(to: CGPoint(x: width, y: 1))
            band.addLine(to: CGPoint(x: width, y: max(right - 1, 1)))
            band.addCurve(
                to: CGPoint(x: 0, y: max(left - 1, 1)),
                control1: CGPoint(x: width * 0.45, y: max(right - 1, 1)),
                control2: CGPoint(x: width * 0.55, y: max(left - 1, 1)))
            band.closeSubpath()
            let gradient = Gradient(colors: [
                SylvraColor.diffRemoved.opacity(0.42), SylvraColor.diffAdded.opacity(0.42),
            ])
            context.fill(
                band, with: .linearGradient(gradient, startPoint: .zero, endPoint: CGPoint(x: width, y: 0)))
            var edges = Path()
            edges.move(to: CGPoint(x: 0, y: 1))
            edges.addLine(to: CGPoint(x: width, y: 1))
            edges.move(to: CGPoint(x: width, y: max(right - 1, 1)))
            edges.addCurve(
                to: CGPoint(x: 0, y: max(left - 1, 1)),
                control1: CGPoint(x: width * 0.45, y: max(right - 1, 1)),
                control2: CGPoint(x: width * 0.55, y: max(left - 1, 1)))
            let edgeGradient = Gradient(colors: [
                SylvraColor.diffRemoved.opacity(0.85), SylvraColor.diffAdded.opacity(0.85),
            ])
            context.stroke(
                edges, with: .linearGradient(edgeGradient, startPoint: .zero, endPoint: CGPoint(x: width, y: 0)),
                lineWidth: 1.5)
        }
        .background(SylvraColor.codeSurface)
        .frame(height: rowHeight)
        .clipped()
        .accessibilityHidden(true)
    }
}

/// Glowing bar at the gutter edge of changed lines (pure).
private struct ChangeBar: View {
    let kind: DiffLine.Kind

    var body: some View {
        if let accent = DiffColors.accent(kind) {
            Capsule()
                .fill(accent)
                .frame(width: 3)
                .padding(.vertical, 1)
                .shadow(color: accent.opacity(0.7), radius: 3)
        } else {
            Color.clear.frame(width: 3)
        }
    }
}

/// Subtle diagonal hatching for the empty side of a side-by-side row (pure).
private struct HatchPattern: View {
    var body: some View {
        Canvas { context, size in
            var path = Path()
            var x: CGFloat = -size.height
            while x < size.width {
                path.move(to: CGPoint(x: x, y: size.height))
                path.addLine(to: CGPoint(x: x + size.height, y: 0))
                x += 7
            }
            context.stroke(path, with: .color(.secondary.opacity(0.10)), lineWidth: 1)
        }
    }
}

private struct LineNumber: View {
    let number: Int?
    let kind: DiffLine.Kind

    init(_ number: Int?, kind: DiffLine.Kind) {
        self.number = number
        self.kind = kind
    }

    var body: some View {
        Text(number.map(String.init) ?? "")
            .font(.system(size: 11, weight: kind == .context ? .regular : .semibold, design: .monospaced))
            .foregroundStyle(DiffColors.accent(kind).map { AnyShapeStyle($0.opacity(0.9)) } ?? AnyShapeStyle(.tertiary))
            .frame(width: 34, alignment: .trailing)
            .padding(.trailing, 8)
    }
}

#Preview {
    let hunk = UnifiedDiffParser.parse(DemoDiffLoader.diff).first?.hunks.first
    VStack(spacing: 0) {
        if let hunk {
            ForEach(Array(SideBySideRow.rows(for: hunk).enumerated()), id: \.offset) { _, row in
                SideBySideRowView(row: row) { _, _, _ in }
            }
        }
    }
    .frame(width: 900)
}
