import DesignSystem
import SwiftUI
import SylvraCore

/// One pull request in the inbox (pure, presentational).
struct InboxRowView: View {
    let pullRequest: PullRequestSummary
    /// The reviewer acted last: the row steps back and says so.
    var isWaitingOnOthers = false

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
                activityLabel
            }
        }
        .padding(.vertical, 3)
        .opacity(isWaitingOnOthers ? 0.55 : 1)
    }

    @ViewBuilder private var activityLabel: some View {
        if isWaitingOnOthers, let since = pullRequest.viewerActivity?.lastActionAt {
            Label {
                Text(
                    "Waiting on others · you \(since, format: .relative(presentation: .numeric, unitsStyle: .narrow))"
                )
            } icon: {
                Image(systemName: "hourglass")
            }
            .font(.caption2)
            .foregroundStyle(.secondary)
            .lineLimit(1)
            .help("You commented or reviewed last — nothing to do until someone responds")
        } else if pullRequest.viewerActivity?.hasNewActivity == true {
            Label("New activity since your last comment", systemImage: "circle.fill")
                .font(.caption2.weight(.medium))
                .imageScale(.small)
                .foregroundStyle(SylvraColor.brandPrimary)
                .lineLimit(1)
        }
    }
}

#Preview {
    List {
        ForEach(DemoInboxLoader.sections[.myTeams] ?? []) {
            InboxRowView(pullRequest: $0, isWaitingOnOthers: $0.isWaitingOnOthers)
        }
    }
    .frame(width: 280)
}
