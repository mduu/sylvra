import DesignSystem
import SwiftUI

/// *Ask AI* and *Copy* next to code selected in the diff (pure). Sits on the selection's last line.
struct DiffSelectionActionsView: View {
    var askAI: (() -> Void)?
    var copy: (() -> Void)?

    var body: some View {
        HStack(spacing: 2) {
            if let askAI {
                Button(action: askAI) {
                    Label("Ask AI", systemImage: "sparkles")
                        .foregroundStyle(AIAccent.border)
                }
                .help("Discuss the selected code privately with the AI agent — nothing is posted")
            }
            if let copy {
                Button(action: copy) {
                    Label("Copy", systemImage: "doc.on.doc")
                        .labelStyle(.iconOnly)
                        .foregroundStyle(.secondary)
                }
                .help("Copy the selected code")
            }
        }
        .buttonStyle(.borderless)
        .font(.system(size: 11, weight: .semibold))
        .padding(.horizontal, 7)
        .frame(height: 18)
        .background(SylvraColor.surfaceElevated, in: Capsule())
        .overlay(Capsule().strokeBorder(AIAccent.border, lineWidth: 1))
        .shadow(color: .black.opacity(0.12), radius: 3, y: 1)
        .fixedSize()
    }
}

#Preview("Selection actions") {
    DiffSelectionActionsView(askAI: {}, copy: {})
        .padding()
        .background(SylvraColor.codeSurface)
}
