import AppKit
import DesignSystem
import SwiftUI
import SylvraCore

/// AI reading-order position and reason below a file name (AI accent, pure).
struct ReadingReasonView: View {
    let number: Int
    let step: ReadingStep

    var body: some View {
        HStack(spacing: 5) {
            Text(verbatim: "\(number)")
                .font(.system(size: 9.5, weight: .bold).monospacedDigit())
                .foregroundStyle(.white)
                .frame(minWidth: 15, minHeight: 15)
                .background(AIAccent.border, in: Circle())
            if step.isRisky {
                Image(systemName: "exclamationmark.triangle.fill").font(.caption2).foregroundStyle(
                    SylvraColor.accentGold)
            }
            Text(step.reason).font(.caption).foregroundStyle(.secondary).lineLimit(1)
        }
        .help("Suggested reading order (AI)")
    }
}
