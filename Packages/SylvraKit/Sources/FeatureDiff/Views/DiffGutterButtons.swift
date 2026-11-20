import AppKit
import DesignSystem
import SwiftUI

/// *Open in IDE* for one line: the IDE's name (help text) and the action.
struct GutterIDEAction {
    let name: String
    let line: Int
    let open: () -> Void
}

/// Buttons shown in the gutter while the line is hovered: `+` comments (⇧-click extends a range), the second
/// opens the line in the IDE.
struct LineGutterButtons: View {
    let isHovered: Bool
    let comment: ((_ extendsRange: Bool) -> Void)?
    let openInIDE: GutterIDEAction?

    var body: some View {
        HStack(spacing: 2) {
            ZStack {
                if let comment, isHovered {
                    Button {
                        comment(NSEvent.modifierFlags.contains(.shift))
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
            .frame(width: 16)
            ZStack {
                if let openInIDE, isHovered {
                    Button(action: openInIDE.open) {
                        Image(systemName: "arrow.up.forward.app")
                            .font(.system(size: 10, weight: .semibold))
                            .foregroundStyle(.secondary)
                            .frame(width: 16, height: 16)
                            .background(SylvraColor.codeSurface, in: RoundedRectangle(cornerRadius: 4))
                            .overlay(RoundedRectangle(cornerRadius: 4).strokeBorder(.separator))
                    }
                    .buttonStyle(.plain)
                    .help("Open in \(openInIDE.name) at line \(openInIDE.line)")
                    .transition(.scale(scale: 0.6).combined(with: .opacity))
                }
            }
            .frame(width: 16)
        }
        .padding(.leading, 4)
        .frame(width: 38, alignment: .leading)
        .animation(.snappy(duration: 0.12), value: isHovered)
    }
}

extension DiffFileBodyView {
    /// *Open in IDE* at a line; removed lines open where they were (the next line that still exists).
    func ideAction(_ line: DiffLine?, in hunk: Hunk) -> GutterIDEAction? {
        guard let ide, let line else { return nil }
        let headLine = hunk.headLine(for: line)
        return GutterIDEAction(name: ide.name, line: headLine) { ide.open(path, headLine) }
    }
}

#Preview("Gutter buttons") {
    HStack(spacing: 12) {
        LineGutterButtons(
            isHovered: true, comment: { _ in }, openInIDE: GutterIDEAction(name: "Rider", line: 42) {})
        LineGutterButtons(isHovered: false, comment: { _ in }, openInIDE: nil)
    }
    .padding()
    .background(SylvraColor.codeGutter)
}
