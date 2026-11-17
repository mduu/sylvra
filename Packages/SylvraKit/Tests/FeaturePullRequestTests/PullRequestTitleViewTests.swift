import SwiftUI
import SylvraCore
import Testing

@testable import FeaturePullRequest

@MainActor
struct PullRequestTitleViewTests {
    @Test func boxIsWiderInWideWindows() {
        #expect(PullRequestTitleView.narrowWidth >= 380)
        #expect(PullRequestTitleView.wideWidth > PullRequestTitleView.narrowWidth)
    }

    @Test func statusLineNamesApprovalsAndChecks() {
        let detail = DemoPullRequestDetailLoader.detail(for: .init(owner: "acme", repository: "billing", number: 1234))
        #expect(PullRequestTitleView.approvals(detail.approvalStatus)?.text == "1 of 2 approvals")
        #expect(PullRequestTitleView.checks(detail)?.text == "1 check failing")
        let approved = ApprovalStatus(reviewers: [], rules: nil, reviewDecision: .approved)
        #expect(PullRequestTitleView.approvals(approved)?.text == "Approved")
        #expect(PullRequestTitleView.approvals(ApprovalStatus(reviewers: [], rules: nil, reviewDecision: .none)) == nil)
    }
}
