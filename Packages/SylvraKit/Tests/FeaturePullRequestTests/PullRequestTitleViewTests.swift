import SwiftUI
import SylvraCore
import Testing

@testable import FeaturePullRequest

@MainActor
struct PullRequestTitleViewTests {
    @Test func boxGrowsInStepsWithTheWindow() {
        let width = PullRequestTitleView.width(forWindowWidth:current:)
        #expect(width(1470, 400) == 400)
        #expect(width(1800, 400) == 560)
        #expect(width(2718, 400) == 880)
        // Near a step boundary the box keeps its width (no flicker while resizing).
        #expect(width(1990, 720) == 720)
        #expect(width(2030, 560) == 560)
        #expect(width(1950, 720) == 560)
        #expect(width(2060, 560) == 720)
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
