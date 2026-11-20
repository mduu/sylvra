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
    /// A click on the header outside its buttons: shows the file in the navigator.
    var select: () -> Void = {}
    /// Position and reason in the AI reading order.
    var readingStep: (number: Int, step: ReadingStep)?
    /// Puts text on the clipboard (path or file name).
    var copy: (String) -> Void = { DiffCopy.toClipboard($0) }

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
                // A click on the name offers to copy the path or the file name.
                Menu {
                    Button("Copy Path", systemImage: "doc.on.doc") { copy(file.path) }
                    Button("Copy File Name", systemImage: "textformat") { copy(file.fileName) }
                } label: {
                    HStack(spacing: 0) {
                        if !file.directory.isEmpty {
                            // The folder gives way first; the file name stays readable.
                            Text(file.directory + "/").foregroundStyle(.secondary).truncationMode(.head)
                        }
                        Text(file.fileName).fontWeight(.semibold).layoutPriority(1)
                    }
                    .font(.system(size: 12.5, design: .monospaced))
                    .lineLimit(1)
                }
                .menuStyle(.button)
                .buttonStyle(.plain)
                .menuIndicator(.hidden)
                .help("Copy the path or the file name")
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
        .contentShape(Rectangle())
        .onTapGesture(perform: select)
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
