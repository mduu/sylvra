import DesignSystem
import SwiftUI
import SylvraCore

/// Where the approvals stand (pure): "1 of 2 approvals" with dots, then what is still missing — more
/// approvals, code owners, people asked to review, requested changes.
struct ApprovalSummaryView: View {
    let status: ApprovalStatus

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(spacing: 6) {
                if status.isSatisfied {
                    Label("Approvals complete", systemImage: "checkmark.seal.fill").foregroundStyle(.green)
                } else if let required = status.requiredApprovals, required > 0 {
                    dots(required: required)
                    Text("\(status.approvedBy.count) of \(required) approvals")
                } else {
                    Text("\(status.approvedBy.count) approvals")
                }
            }
            .font(.callout.weight(.medium))
            ForEach(lines, id: \.self) { line in
                Text(verbatim: line).font(.caption).foregroundStyle(.secondary)
                    .fixedSize(horizontal: false, vertical: true)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
        .padding(.bottom, 2)
    }

    private var lines: [String] {
        guard !status.isSatisfied else { return [] }
        var lines: [String] = []
        if !status.changesRequestedBy.isEmpty {
            lines.append(String(localized: "Changes requested by \(status.changesRequestedBy.joined(separator: ", "))"))
        }
        if let missing = status.missingApprovals, missing > 0 {
            lines.append(
                missing == 1
                    ? String(localized: "1 more approval needed")
                    : String(localized: "\(missing) more approvals needed"))
        }
        if !status.codeOwnersNeeded.isEmpty {
            lines.append(
                String(localized: "Code owner review needed: \(status.codeOwnersNeeded.joined(separator: ", "))"))
        }
        let waiting = status.waitingFor.filter { !status.codeOwnersNeeded.contains($0) }
        if !waiting.isEmpty {
            lines.append(String(localized: "Waiting for \(waiting.joined(separator: ", "))"))
        }
        if status.requiredApprovals == nil, status.reviewDecision == .reviewRequired {
            lines.append(String(localized: "Approval required — the number isn't visible to you (branch rules)."))
        }
        return lines
    }

    /// One dot per required approval, filled for each one given.
    private func dots(required: Int) -> some View {
        HStack(spacing: 3) {
            ForEach(0..<min(required, 6), id: \.self) { index in
                Circle()
                    .fill(index < status.approvedBy.count ? AnyShapeStyle(.green) : AnyShapeStyle(.quaternary))
                    .frame(width: 8, height: 8)
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    let reviewers: [PullRequestDetail.Reviewer] = [
        .init(name: "jmeier", user: UserRef(login: "jmeier", name: "Jonas Meier"), isTeam: false, status: .approved),
        .init(name: "mduu", user: UserRef(login: "mduu", name: "Marc Dürst"), isTeam: false, status: .pending),
        .init(name: "@acme/billing", user: nil, isTeam: true, status: .pending, isCodeOwner: true),
    ]
    VStack(alignment: .leading, spacing: 16) {
        ApprovalSummaryView(
            status: ApprovalStatus(
                reviewers: reviewers, rules: ApprovalRules(requiredApprovals: 2, requiresCodeOwnerReview: true),
                reviewDecision: .reviewRequired))
        ApprovalSummaryView(status: ApprovalStatus(reviewers: reviewers, rules: nil, reviewDecision: .reviewRequired))
        ApprovalSummaryView(status: ApprovalStatus(reviewers: reviewers, rules: nil, reviewDecision: .approved))
    }
    .padding()
    .frame(width: 320)
}
