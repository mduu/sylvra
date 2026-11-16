import DesignSystem
import SwiftUI
import SylvraCore

/// Banner while reviewing one commit: which commit, step to the previous / next one, back to all changes (pure).
struct CommitModeBar: View {
    let commit: Commit
    let number: Int
    let count: Int
    var isLoading = false
    var previous: () -> Void = {}
    var next: () -> Void = {}
    var showAll: () -> Void = {}

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 8) {
                Image(systemName: "point.topleft.down.to.point.bottomright.curvepath")
                    .foregroundStyle(SylvraColor.brandPrimary)
                Text("Commit \(number) of \(count)").font(.callout.weight(.semibold))
                Text(commit.shortSHA).font(.caption.monospaced()).foregroundStyle(.secondary)
                Text(commit.subject).font(.callout).lineLimit(1).truncationMode(.tail)
                if isLoading { ProgressView().controlSize(.small) }
                Spacer(minLength: 8)
                ControlGroup {
                    Button(action: previous) { Label("Previous commit", systemImage: "chevron.left") }
                        .disabled(number <= 1)
                        .help("Previous commit (⌥[)")
                    Button(action: next) { Label("Next commit", systemImage: "chevron.right") }
                        .disabled(number >= count)
                        .help("Next commit (⌥])")
                }
                .labelStyle(.iconOnly)
                .fixedSize()
                Button("All changes", action: showAll)
                    .help("Back to all changes of the pull request")
            }
            Text(
                "Showing only this commit. Comments and AI findings refer to the whole pull request, so they're hidden here."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
        .controlSize(.small)
        .padding(.horizontal, 12)
        .padding(.vertical, 8)
        .background(SylvraColor.brandTint.opacity(0.5))
        .overlay(alignment: .bottom) { Rectangle().fill(SylvraColor.brandSecondary.opacity(0.4)).frame(height: 1) }
    }
}

#Preview {
    CommitModeBar(
        commit: Commit(
            sha: "3be7d12f0e9d8c7b6a5f4e3d2c1b0a9f8e7d6c5b", subject: "Add ExportFormat and export(_:as:)",
            author: UserRef(login: "lkeller"), authoredAt: .now),
        number: 2, count: 4
    )
    .frame(width: 720)
}
