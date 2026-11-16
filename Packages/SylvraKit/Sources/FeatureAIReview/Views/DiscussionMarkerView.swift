import DesignSystem
import SwiftUI

/// Marker below discussed lines in the diff: these lines were discussed privately with the agent (pure).
public struct DiscussionMarkerView: View {
    private let open: () -> Void

    public init(open: @escaping () -> Void) {
        self.open = open
    }

    public var body: some View {
        Button(action: open) {
            Label("Discussed with Claude — private", systemImage: "bubble.left.and.text.bubble.right")
                .aiFont(.caption)
                .padding(.horizontal, 9)
                .padding(.vertical, 4)
                .background(AIAccent.cardBackground, in: Capsule())
                .overlay(Capsule().strokeBorder(AIAccent.border, lineWidth: 1))
        }
        .buttonStyle(.plain)
        .help("Open the discussion in the AI chat (nothing was posted to GitHub)")
    }
}

#Preview("Discussion marker") {
    DiscussionMarkerView(open: {}).padding()
}
