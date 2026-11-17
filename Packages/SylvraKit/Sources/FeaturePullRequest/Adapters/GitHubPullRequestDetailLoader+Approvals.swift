import Foundation
import Platform
import SylvraCore

extension GitHubPullRequestDetailLoader {
    /// The approval rules of the base branch from rulesets and branch protection. Each source is asked
    /// separately and may fail (some setups only show them to admins); `nil` when neither is visible.
    func loadApprovalRules(for id: PullRequestID) async -> ApprovalRules? {
        let variables: [String: GraphQLValue] = [
            "owner": .string(id.owner), "name": .string(id.repository), "number": .int(id.number),
        ]
        async let rulesets = try? client.graphQL(Self.rulesetQuery, variables: variables, as: RulesetResponse.self)
        async let protection = try? client.graphQL(
            Self.protectionQuery, variables: variables, as: ProtectionResponse.self)
        var rules: [ApprovalRules] = []
        if let nodes = await rulesets?.repository?.pullRequest?.baseRef?.rules?.nodes {
            rules += nodes.compactMap { $0?.parameters }.compactMap(\.approvalRules)
        }
        if let rule = await protection?.repository?.pullRequest?.baseRef?.branchProtectionRule {
            rules.append(rule.approvalRules)
        }
        return ApprovalRules.combine(rules)
    }

    static let rulesetQuery = """
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) { pullRequest(number: $number) { baseRef {
            rules(first: 50) { nodes { parameters {
              ... on PullRequestParameters { requiredApprovingReviewCount requireCodeOwnerReview }
            } } }
          } } }
        }
        """

    static let protectionQuery = """
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) { pullRequest(number: $number) { baseRef {
            branchProtectionRule { requiresApprovingReviews requiredApprovingReviewCount requiresCodeOwnerReviews }
          } } }
        }
        """
}

struct RulesetResponse: Decodable, Sendable {
    let repository: Repository?
    struct Repository: Decodable, Sendable { let pullRequest: PullRequest? }
    struct PullRequest: Decodable, Sendable { let baseRef: Ref? }
    struct Ref: Decodable, Sendable { let rules: Rules? }
    struct Rules: Decodable, Sendable { let nodes: [Rule?] }
    struct Rule: Decodable, Sendable { let parameters: Parameters? }

    /// Only pull request rules carry these fields; other rule types decode as empty.
    struct Parameters: Decodable, Sendable {
        let requiredApprovingReviewCount: Int?
        let requireCodeOwnerReview: Bool?

        var approvalRules: ApprovalRules? {
            guard requiredApprovingReviewCount != nil || requireCodeOwnerReview != nil else { return nil }
            return ApprovalRules(
                requiredApprovals: requiredApprovingReviewCount ?? 0,
                requiresCodeOwnerReview: requireCodeOwnerReview ?? false)
        }
    }
}

struct ProtectionResponse: Decodable, Sendable {
    let repository: Repository?
    struct Repository: Decodable, Sendable { let pullRequest: PullRequest? }
    struct PullRequest: Decodable, Sendable { let baseRef: Ref? }
    struct Ref: Decodable, Sendable { let branchProtectionRule: Rule? }

    struct Rule: Decodable, Sendable {
        let requiresApprovingReviews: Bool?
        let requiredApprovingReviewCount: Int?
        let requiresCodeOwnerReviews: Bool?

        var approvalRules: ApprovalRules {
            ApprovalRules(
                requiredApprovals: requiresApprovingReviews == false ? 0 : requiredApprovingReviewCount ?? 0,
                requiresCodeOwnerReview: requiresCodeOwnerReviews ?? false)
        }
    }
}
