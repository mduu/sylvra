import DesignSystem
import SwiftUI
import SylvraCore

/// One pull request in the inbox (pure, presentational).
struct InboxRowView: View {
    let pullRequest: PullRequestSummary

    var body: some View {
        HStack(alignment: .top, spacing: 10) {
            AvatarView(pullRequest.author, size: 26)
            VStack(alignment: .leading, spacing: 3) {
                HStack(spacing: 6) {
                    Text(pullRequest.title)
                        .font(.callout.weight(.semibold))
                        .lineLimit(1)
                    if pullRequest.isDraft {
                        Text("Draft")
                            .font(.caption2.weight(.semibold))
                            .padding(.horizontal, 5)
                            .padding(.vertical, 1)
                            .background(.quaternary, in: Capsule())
                    }
                }
                HStack(spacing: 6) {
                    Text(verbatim: "\(pullRequest.id.repository) #\(pullRequest.id.number)")
                    Text(verbatim: "+\(pullRequest.additions) −\(pullRequest.deletions)")
                        .monospacedDigit()
                    CheckStateBadge(pullRequest.checkState)
                    Spacer(minLength: 0)
                    Text(pullRequest.updatedAt, format: .relative(presentation: .numeric, unitsStyle: .narrow))
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .lineLimit(1)
            }
        }
        .padding(.vertical, 3)
    }
}

#Preview {
    List {
        ForEach(DemoInboxLoader.sections[.myTeams] ?? []) { InboxRowView(pullRequest: $0) }
    }
    .frame(width: 280)
}
