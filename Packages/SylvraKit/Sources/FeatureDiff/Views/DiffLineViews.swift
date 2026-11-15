import SwiftUI

private let diffRowHeight: CGFloat = 20
private let codeFont = Font.system(size: 12, design: .monospaced)

/// One line in the inline (unified) layout (pure).
struct InlineLineView: View {
    let line: DiffLine

    var body: some View {
        HStack(spacing: 0) {
            LineNumber(line.oldNumber)
            LineNumber(line.newNumber)
            Text(marker).frame(width: 16).foregroundStyle(.secondary)
            Text(line.attributedText)
                .lineLimit(1)
                .frame(maxWidth: .infinity, alignment: .leading)
        }
        .font(codeFont)
        .frame(height: diffRowHeight)
        .background(DiffColors.background(line.kind))
    }

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

    var body: some View {
        HStack(spacing: 0) {
            half(row.left, number: row.left?.oldNumber)
            Divider()
            half(row.right, number: row.right?.newNumber)
        }
        .font(codeFont)
        .frame(height: diffRowHeight)
    }

    private func half(_ line: DiffLine?, number: Int?) -> some View {
        HStack(spacing: 0) {
            LineNumber(number)
            if let line {
                Text(line.attributedText)
                    .lineLimit(1)
                    .padding(.leading, 6)
                    .frame(maxWidth: .infinity, alignment: .leading)
            } else {
                Spacer()
            }
        }
        .frame(maxWidth: .infinity)
        .background(line.map { DiffColors.background($0.kind) } ?? DiffColors.emptyBackground)
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
            .frame(width: 44, alignment: .trailing)
            .padding(.trailing, 6)
    }
}
