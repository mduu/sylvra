import DesignSystem
import SwiftUI
import SylvraCore

/// Overview tab: merge status, description, people and metadata (pure).
struct OverviewView: View {
    let detail: PullRequestDetail
    let open: (URL) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 18) {
            if !detail.mergeStatus.reasons.isEmpty {
                MergeStatusCardView(status: detail.mergeStatus, reasons: detail.mergeReasons)
            }
            if !detail.involvement.isEmpty {
                InvolvementCardView(involvement: detail.involvement, open: open)
            }
            section("Description") {
                if detail.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
                    Text("No description provided.").foregroundStyle(.secondary)
                } else {
                    MarkdownView(text: detail.body)
                }
            }
            section("Reviewers") {
                if detail.state == .open {
                    ApprovalSummaryView(status: detail.approvalStatus)
                }
                ForEach(detail.reviewers) { reviewer in
                    ReviewerRowView(reviewer: reviewer)
                }
                if detail.reviewers.isEmpty { Text("No reviewers").foregroundStyle(.secondary) }
            }
            if !detail.labels.isEmpty {
                section("Labels") {
                    FlowChips {
                        ForEach(detail.labels, id: \.self) { label in
                            StatusChip(label.name, systemImage: "tag", tint: Color(hex: label.color) ?? .secondary)
                        }
                    }
                }
            }
            if !detail.linkedIssues.isEmpty {
                section("Linked issues") {
                    ForEach(detail.linkedIssues, id: \.self) { issue in
                        Button {
                            if let url = issue.url { open(url) }
                        } label: {
                            Label {
                                Text(verbatim: "#\(issue.number) \(issue.title)")
                            } icon: {
                                Image(systemName: "smallcircle.filled.circle")
                            }
                        }
                        .buttonStyle(.link)
                    }
                }
            }
            section("Refs") {
                VStack(alignment: .leading, spacing: 2) {
                    Text(verbatim: "head  \(detail.summary.headRefName) · \(detail.headSHA.prefix(7))")
                    Text(verbatim: "base  \(detail.summary.baseRefName) · \(detail.baseSHA.prefix(7))")
                    if let milestone = detail.milestone { Text(verbatim: "milestone  \(milestone)") }
                }
                .font(.caption.monospaced())
                .foregroundStyle(.secondary)
                .textSelection(.enabled)
            }
        }
    }

    private func section<Content: View>(_ title: LocalizedStringKey, @ViewBuilder content: () -> Content) -> some View {
        VStack(alignment: .leading, spacing: 8) {
            Text(title)
                .font(.caption.weight(.semibold))
                .textCase(.uppercase)
                .foregroundStyle(.secondary)
            content()
        }
    }
}

/// Merge blockers in plain words.
struct MergeStatusCardView: View {
    let status: MergeStatus
    /// The reasons to list (e.g. with the review part spelled out); defaults to the status's own.
    var reasons: [String]?

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Label(status.title, systemImage: status.symbol)
                .font(.callout.weight(.semibold))
                .foregroundStyle(status.tint)
            ForEach(reasons ?? status.reasons, id: \.self) { reason in
                Text(verbatim: "· \(reason)").font(.callout).foregroundStyle(.secondary)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(12)
        .background(status.tint.opacity(0.08), in: RoundedRectangle(cornerRadius: 10))
    }
}

struct ReviewerRowView: View {
    let reviewer: PullRequestDetail.Reviewer

    var body: some View {
        HStack(spacing: 8) {
            if let user = reviewer.user {
                AvatarView(user, size: 22)
            } else {
                Image(systemName: "person.2.fill")
                    .font(.caption)
                    .frame(width: 22, height: 22)
                    .background(.quaternary, in: Circle())
            }
            Text(reviewer.user?.displayName ?? reviewer.name).lineLimit(1)
            if reviewer.isCodeOwner {
                Image(systemName: "shield.lefthalf.filled")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .help("Code owner (requested because of CODEOWNERS)")
                    .accessibilityLabel("Code owner")
            }
            Spacer(minLength: 4)
            StatusChip(reviewer.status.title, systemImage: reviewer.status.symbol, tint: reviewer.status.tint)
        }
    }
}

extension PullRequestDetail.Reviewer.Status {
    var title: String {
        switch self {
        case .approved: String(localized: "Approved")
        case .changesRequested: String(localized: "Changes")
        case .commented: String(localized: "Commented")
        case .dismissed: String(localized: "Dismissed")
        case .pending: String(localized: "Pending")
        }
    }

    var symbol: String {
        switch self {
        case .approved: "checkmark"
        case .changesRequested: "exclamationmark"
        case .commented: "text.bubble"
        case .dismissed: "xmark"
        case .pending: "clock"
        }
    }

    var tint: Color {
        switch self {
        case .approved: .green
        case .changesRequested: .red
        case .pending: SylvraColor.brandPrimary
        case .commented, .dismissed: .secondary
        }
    }
}

extension Color {
    /// Creates a color from a GitHub label hex string (`RRGGBB`).
    init?(hex: String) {
        guard hex.count == 6, let value = UInt32(hex, radix: 16) else { return nil }
        self.init(
            red: Double((value >> 16) & 0xFF) / 255,
            green: Double((value >> 8) & 0xFF) / 255,
            blue: Double(value & 0xFF) / 255
        )
    }
}
