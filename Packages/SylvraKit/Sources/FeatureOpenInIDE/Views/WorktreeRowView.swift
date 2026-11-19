import DesignSystem
import SwiftUI
import SylvraCore

/// One worktree in the settings list (pure).
struct WorktreeRowView: View {
    let entry: WorktreesModel.Entry
    let reveal: () -> Void
    let remove: () -> Void

    var body: some View {
        HStack(alignment: .firstTextBaseline, spacing: 10) {
            Image(systemName: entry.record.purpose == .agent ? "sparkles" : "hammer")
                .foregroundStyle(
                    entry.record.purpose == .agent ? AnyShapeStyle(AIAccent.border) : AnyShapeStyle(.secondary)
                )
                .frame(width: 18)
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(entry.record.repository).fontWeight(.medium)
                    if let number = entry.record.pullRequest?.number {
                        Text(verbatim: "#\(number)").foregroundStyle(SylvraColor.brandPrimary)
                    }
                }
                Text(details).font(.caption).foregroundStyle(.secondary)
                if entry.hasChanges {
                    Label("Changed files — only removed on request", systemImage: "exclamationmark.triangle")
                        .font(.caption)
                        .foregroundStyle(SylvraColor.accentGold)
                }
            }
            Spacer(minLength: 8)
            Button("Show in Finder", systemImage: "folder", action: reveal)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Show in Finder")
            Button("Remove", systemImage: "trash", action: remove)
                .labelStyle(.iconOnly)
                .buttonStyle(.borderless)
                .help("Remove this worktree")
        }
        .padding(.vertical, 2)
    }

    private var details: String {
        let purpose =
            entry.record.purpose == .agent
            ? String(localized: "AI review and chat") : String(localized: "IDE and terminal")
        let used = entry.record.lastUsedAt.formatted(.relative(presentation: .named))
        let clone =
            entry.isInUserClone
            ? String(localized: "in your clone") : String(localized: "in Sylvra's clone")
        return String(localized: "\(purpose) · used \(used) · \(clone)")
    }
}

#Preview {
    let record = WorktreeRecord(
        path: "/tmp/agent-worktrees/acme/billing/pr-1234", purpose: .agent,
        pullRequest: PullRequestID(owner: "acme", repository: "billing", number: 1234),
        clonePath: "/Users/me/Dev/billing",
        createdAt: .now.addingTimeInterval(-86_400), lastUsedAt: .now.addingTimeInterval(-3_600))
    Form {
        WorktreeRowView(
            entry: .init(record: record, hasChanges: false, isInUserClone: true), reveal: {}, remove: {})
        WorktreeRowView(
            entry: .init(record: record, hasChanges: true, isInUserClone: false), reveal: {}, remove: {})
    }
    .formStyle(.grouped)
    .frame(width: 520)
}
