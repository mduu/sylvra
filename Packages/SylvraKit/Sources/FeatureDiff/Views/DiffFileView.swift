import SwiftUI

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
struct DiffFileBodyView: View {
    let hunks: [Hunk]
    let layout: DiffScreenModel.Layout

    var body: some View {
        VStack(spacing: 0) {
            ForEach(Array(hunks.enumerated()), id: \.offset) { _, hunk in
                HunkHeaderView(hunk: hunk)
                switch layout {
                case .inline:
                    ForEach(Array(hunk.lines.enumerated()), id: \.offset) { _, line in InlineLineView(line: line) }
                case .sideBySide:
                    ForEach(Array(SideBySideRow.rows(for: hunk).enumerated()), id: \.offset) { _, row in
                        SideBySideRowView(row: row)
                    }
                }
            }
        }
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
