import AppKit
import DesignSystem
import SwiftUI
import SylvraCore

private let diffRowHeight: CGFloat = 20
private let codeFont = Font.system(size: 12, design: .monospaced)

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
            CommentGutter(isHovered: isHovered, action: commentAction)
            HStack(spacing: 0) {
                LineNumber(line.oldNumber)
                LineNumber(line.newNumber)
            }
            .commentOnClick(commentAction)
            Text(marker).frame(width: 16).foregroundStyle(.secondary)
            Text(line.attributedText(language: language))
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(codeFont)
        .frame(height: diffRowHeight)
        .background(DiffColors.background(line.kind))
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
    var onComment: CommentRequest?

    var body: some View {
        HStack(spacing: 0) {
            SideBySideHalf(line: row.left, number: row.left?.oldNumber, side: .left, onComment: onComment)
            Divider()
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
            CommentGutter(isHovered: isHovered && line != nil, action: commentAction)
            LineNumber(number).commentOnClick(commentAction)
            if let line {
                Text(line.attributedText(language: language))
                    .lineLimit(1)
                    .padding(.leading, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .background(line.map { DiffColors.background($0.kind) } ?? DiffColors.emptyBackground)
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

/// `@@ … @@ section` separator (pure).
struct HunkHeaderView: View {
    let hunk: Hunk

    var body: some View {
        Text(hunk.section.isEmpty ? hunk.header : hunk.section)
            .font(.system(size: 11, design: .monospaced))
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .padding(.horizontal, 12)
            .frame(maxWidth: .infinity, minHeight: 24, alignment: .leading)
            .background(DiffColors.hunkBackground)
    }
}

private struct LineNumber: View {
    let number: Int?

    init(_ number: Int?) {
        self.number = number
    }

    var body: some View {
        Text(number.map(String.init) ?? "")
            .foregroundStyle(.tertiary)
            .frame(width: 36, alignment: .trailing)
            .padding(.trailing, 6)
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
