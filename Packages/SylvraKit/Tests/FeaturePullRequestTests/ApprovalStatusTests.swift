import Foundation
import SylvraCore
import Testing

@testable import FeaturePullRequest

struct ApprovalStatusTests {
    let reviewers: [PullRequestDetail.Reviewer] = [
        .init(name: "jmeier", user: UserRef(login: "jmeier", name: "Jonas Meier"), isTeam: false, status: .approved),
        .init(name: "mduu", user: UserRef(login: "mduu", name: "Marc Dürst"), isTeam: false, status: .pending),
        .init(name: "@acme/billing", user: nil, isTeam: true, status: .pending, isCodeOwner: true),
    ]

    @Test func spellsOutMissingApprovalsAndCodeOwners() {
        let status = ApprovalStatus(
            reviewers: reviewers, rules: ApprovalRules(requiredApprovals: 2, requiresCodeOwnerReview: true),
            reviewDecision: .reviewRequired)
        #expect(status.approvedBy == ["Jonas Meier"])
        #expect(status.missingApprovals == 1)
        #expect(status.codeOwnersNeeded == ["@acme/billing"])
        #expect(status.waitingFor == ["Marc Dürst", "@acme/billing"])
        #expect(
            status.blockingReasons == [
                "1 more approval needed (1 of 2)", "Code owner review needed: @acme/billing",
            ])
    }

    @Test func codeOwnersOnlyCountWhenTheBranchRequiresThem() {
        let status = ApprovalStatus(
            reviewers: reviewers, rules: ApprovalRules(requiredApprovals: 1, requiresCodeOwnerReview: false),
            reviewDecision: .reviewRequired)
        #expect(status.codeOwnersNeeded.isEmpty)
        #expect(status.missingApprovals == 0)
        // GitHub still says a review is required (e.g. an approval that doesn't count): keep its wording.
        #expect(status.blockingReasons == ["Approving review required"])
    }

    @Test func unknownRulesAndCompleteReviews() {
        let unknown = ApprovalStatus(reviewers: reviewers, rules: nil, reviewDecision: .reviewRequired)
        #expect(unknown.requiredApprovals == nil)
        #expect(unknown.missingApprovals == nil)
        let done = ApprovalStatus(reviewers: reviewers, rules: nil, reviewDecision: .approved)
        #expect(done.isSatisfied)
        #expect(done.blockingReasons.isEmpty)
    }

    @Test func combinesRulesetAndBranchProtectionStrictly() {
        let combined = ApprovalRules.combine([
            ApprovalRules(requiredApprovals: 1, requiresCodeOwnerReview: true),
            ApprovalRules(requiredApprovals: 2, requiresCodeOwnerReview: false),
        ])
        #expect(combined == ApprovalRules(requiredApprovals: 2, requiresCodeOwnerReview: true))
        #expect(ApprovalRules.combine([]) == nil)
    }

    @Test func mergeReasonsReplaceTheGenericReviewLine() {
        let detail = DemoPullRequestDetailLoader.detail(for: .init(owner: "acme", repository: "billing", number: 1234))
        #expect(detail.mergeReasons.contains("1 more approval needed (1 of 2)"))
        #expect(detail.mergeReasons.contains("Code owner review needed: @acme/billing"))
        #expect(!detail.mergeReasons.contains("Approving review required"))
        #expect(detail.mergeReasons.contains { $0.contains("failing") })
    }

    @Test func decodesRulesFromBothSources() throws {
        let rulesets = """
            {"repository":{"pullRequest":{"baseRef":{"rules":{"nodes":[
              {"parameters":{}},
              {"parameters":{"requiredApprovingReviewCount":2,"requireCodeOwnerReview":true}}]}}}}}
            """
        let decoded = try JSONDecoder().decode(RulesetResponse.self, from: Data(rulesets.utf8))
        let rules = decoded.repository?.pullRequest?.baseRef?.rules?.nodes.compactMap { $0?.parameters?.approvalRules }
        #expect(rules == [ApprovalRules(requiredApprovals: 2, requiresCodeOwnerReview: true)])
        let protection = """
            {"repository":{"pullRequest":{"baseRef":{"branchProtectionRule":
              {"requiresApprovingReviews":false,"requiredApprovingReviewCount":3,"requiresCodeOwnerReviews":false}}}}}
            """
        let rule = try JSONDecoder().decode(ProtectionResponse.self, from: Data(protection.utf8))
        #expect(
            rule.repository?.pullRequest?.baseRef?.branchProtectionRule?.approvalRules
                == ApprovalRules(requiredApprovals: 0, requiresCodeOwnerReview: false))
    }
}
