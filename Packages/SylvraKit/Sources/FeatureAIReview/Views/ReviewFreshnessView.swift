import DesignSystem
import SwiftUI

/// Which state of the pull request the AI review saw (pure): a clear hint with *Run again* when new commits
/// arrived since, otherwise when it ran and a quiet *Run again*.
struct ReviewFreshnessView: View {
    let isOutdated: Bool
    let reviewedAt: Date?
    var isEnabled = true
    let runAgain: () -> Void

    var body: some View {
        if isOutdated {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Image(systemName: "arrow.triangle.2.circlepath").foregroundStyle(.orange)
                VStack(alignment: .leading, spacing: 2) {
                    Text("New commits since this review").aiFont(.caption, weight: .semibold)
                    Text("Findings may point at code that changed.").aiFont(.caption).foregroundStyle(.secondary)
                }
                Spacer(minLength: 4)
                Button("Run again", action: runAgain)
                    .buttonStyle(.borderedProminent)
                    .tint(SylvraColor.brandPrimary)
                    .controlSize(.small)
                    .disabled(!isEnabled)
            }
            .padding(8)
            .background(Color.orange.opacity(0.1), in: RoundedRectangle(cornerRadius: 8))
        } else {
            HStack(spacing: 6) {
                if let reviewedAt {
                    Text("Reviewed \(reviewedAt, format: .relative(presentation: .named))")
                        .aiFont(.caption)
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                }
                Spacer(minLength: 4)
                Button("Run again", systemImage: "arrow.clockwise", action: runAgain)
                    .buttonStyle(.borderless)
                    .aiFont(.caption)
                    .disabled(!isEnabled)
                    .help("Review the pull request again with the current diff (⌘⇧R)")
            }
        }
    }
}

#Preview {
    VStack(spacing: 16) {
        ReviewFreshnessView(isOutdated: true, reviewedAt: .now.addingTimeInterval(-7200)) {}
        ReviewFreshnessView(isOutdated: false, reviewedAt: .now.addingTimeInterval(-600)) {}
    }
    .padding()
    .frame(width: 340)
}
