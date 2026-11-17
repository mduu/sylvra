import Foundation
import SylvraCore

/// What the base branch requires before merging (rulesets and branch protection combined).
public struct ApprovalRules: Sendable, Equatable {
    public var requiredApprovals: Int
    public var requiresCodeOwnerReview: Bool

    public init(requiredApprovals: Int, requiresCodeOwnerReview: Bool) {
        self.requiredApprovals = requiredApprovals
        self.requiresCodeOwnerReview = requiresCodeOwnerReview
    }

    /// The strictest of several rules (a ruleset and a branch protection rule can both apply).
    public static func combine(_ rules: [ApprovalRules]) -> ApprovalRules? {
        guard !rules.isEmpty else { return nil }
        return ApprovalRules(
            requiredApprovals: rules.map(\.requiredApprovals).max() ?? 0,
            requiresCodeOwnerReview: rules.contains { $0.requiresCodeOwnerReview })
    }
}

/// Where the approvals of a pull request stand: how many there are, how many the branch needs, and who is
/// still expected to review.
public struct ApprovalStatus: Sendable, Equatable {
    public var approvedBy: [String]
    /// `nil` when the branch rules aren't visible (they need more than read access in some setups).
    public var requiredApprovals: Int?
    public var changesRequestedBy: [String]
    /// Requested reviewers that haven't reviewed yet (people and teams).
    public var waitingFor: [String]
    /// Pending code owner requests that must approve.
    public var codeOwnersNeeded: [String]
    public var reviewDecision: ReviewDecision

    public init(reviewers: [PullRequestDetail.Reviewer], rules: ApprovalRules?, reviewDecision: ReviewDecision) {
        func names(_ status: PullRequestDetail.Reviewer.Status) -> [String] {
            reviewers.filter { $0.status == status }.map(\.displayName)
        }
        approvedBy = names(.approved)
        changesRequestedBy = names(.changesRequested)
        waitingFor = names(.pending)
        requiredApprovals = rules?.requiredApprovals
        codeOwnersNeeded =
            rules?.requiresCodeOwnerReview == true
            ? reviewers.filter { $0.isCodeOwner && $0.status == .pending }.map(\.displayName) : []
        self.reviewDecision = reviewDecision
    }

    /// Approvals still missing to reach the required count (`nil` when the count is unknown).
    public var missingApprovals: Int? {
        requiredApprovals.map { max(0, $0 - approvedBy.count) }
    }

    /// GitHub says the reviews are complete.
    public var isSatisfied: Bool { reviewDecision == .approved }

    /// What still blocks the merge on the review side, in plain words (empty when nothing does).
    public var blockingReasons: [String] {
        guard !isSatisfied else { return [] }
        var reasons: [String] = []
        if !changesRequestedBy.isEmpty {
            reasons.append(String(localized: "Changes requested by \(changesRequestedBy.joined(separator: ", "))"))
        }
        if let missing = missingApprovals, missing > 0, let required = requiredApprovals {
            reasons.append(
                missing == 1
                    ? String(localized: "1 more approval needed (\(approvedBy.count) of \(required))")
                    : String(localized: "\(missing) more approvals needed (\(approvedBy.count) of \(required))"))
        }
        if !codeOwnersNeeded.isEmpty {
            reasons.append(String(localized: "Code owner review needed: \(codeOwnersNeeded.joined(separator: ", "))"))
        }
        if reasons.isEmpty, reviewDecision == .reviewRequired {
            reasons.append(String(localized: "Approving review required"))
        }
        return reasons
    }
}

extension PullRequestDetail.Reviewer {
    /// Team handle or the person's name.
    public var displayName: String { user?.displayName ?? name }
}

extension PullRequestDetail {
    public var approvalStatus: ApprovalStatus {
        ApprovalStatus(reviewers: reviewers, rules: approvalRules, reviewDecision: summary.reviewDecision)
    }

    /// The merge blockers with the review part spelled out (who and how many) where it is known.
    public var mergeReasons: [String] {
        let generic: Set<String> = [
            String(localized: "Approving review required"), String(localized: "Changes requested"),
        ]
        guard mergeStatus.reasons.contains(where: generic.contains) else { return mergeStatus.reasons }
        var reasons: [String] = []
        for reason in mergeStatus.reasons {
            if generic.contains(reason) {
                if !reasons.contains(where: approvalStatus.blockingReasons.contains) {
                    reasons += approvalStatus.blockingReasons
                }
            } else {
                reasons.append(reason)
            }
        }
        return reasons
    }
}
