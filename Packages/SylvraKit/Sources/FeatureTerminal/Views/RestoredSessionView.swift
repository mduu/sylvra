import DesignSystem
import SwiftUI

/// In place of a Claude session that ended when Sylvra quit (pure): where it ran, *Continue* and *Close*.
struct RestoredSessionView: View {
    let title: String
    let directory: String
    let resume: () -> Void
    let close: () -> Void

    var body: some View {
        VStack(spacing: 10) {
            Image(systemName: "arrow.clockwise.circle")
                .font(.largeTitle)
                .foregroundStyle(SylvraColor.accentGold)
            Text("This Claude session ended when Sylvra quit.")
                .font(.headline)
            Text(directory)
                .font(.callout.monospaced())
                .foregroundStyle(.secondary)
                .lineLimit(1)
                .truncationMode(.middle)
            HStack {
                Button("Close", action: close)
                Button("Continue", action: resume)
                    .keyboardShortcut(.defaultAction)
                    .help("Run claude --continue in this folder: picks up the last conversation there")
            }
            .padding(.top, 4)
        }
        .foregroundStyle(SylvraColor.terminalForeground)
        .padding()
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SylvraColor.terminalBackground)
        .accessibilityElement(children: .contain)
        .accessibilityLabel("\(title): ended when Sylvra quit")
    }
}

#Preview {
    RestoredSessionView(
        title: "Claude · #812", directory: "~/Library/Application Support/Sylvra/worktrees/billing-812",
        resume: {}, close: {}
    )
    .frame(width: 700, height: 240)
}
