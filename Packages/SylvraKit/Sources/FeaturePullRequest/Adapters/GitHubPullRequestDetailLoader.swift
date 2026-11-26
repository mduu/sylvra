import Foundation
import Platform
import SylvraCore

/// Loads PR details with one GraphQL request.
public struct GitHubPullRequestDetailLoader: PullRequestDetailLoading {
    let client: GitHubClient

    public init(client: GitHubClient) {
        self.client = client
    }

    public func loadDetail(for id: PullRequestID) async throws -> PullRequestDetail {
        let response = try await client.graphQL(
            Self.query,
            variables: ["owner": .string(id.owner), "name": .string(id.repository), "number": .int(id.number)],
            as: DetailResponse.self
        )
        guard let node = response.repository?.pullRequest else {
            throw GitHubError.graphQL(["Pull request \(id) not found"])
        }
        async let rules = loadApprovalRules(for: id)
        var detail = node.detail
        detail.mergeOptions = node.mergeOptions
        detail.discussion = node.discussion
        detail.approvalRules = await rules
        if let login = response.viewer?.login {
            detail.involvement = node.involvement(of: login)
        }
        return detail
    }

    // swiftlint:disable line_length
    static let query = """
        query($owner: String!, $name: String!, $number: Int!) {
          viewer { login }
          repository(owner: $owner, name: $name) {
            pullRequest(number: $number) {
              id number title url isDraft createdAt updatedAt additions deletions changedFiles
              viewerCanEnableAutoMerge viewerCanMergeAsAdmin autoMergeRequest { mergeMethod }
              headRefName baseRefName headRefOid baseRefOid reviewDecision mergeable mergeStateStatus state
              body
              repository { name owner { login } viewerPermission viewerDefaultMergeMethod mergeCommitAllowed squashMergeAllowed rebaseMergeAllowed }
              headRepositoryOwner { login }
              author { login avatarUrl ... on User { name } }
              labels(first: 20) { nodes { name color } }
              assignees(first: 10) { nodes { login avatarUrl name } }
              milestone { title }
              closingIssuesReferences(first: 5) { nodes { number title url } }
              reviewRequests(first: 20) { nodes { asCodeOwner requestedReviewer { __typename ... on User { login avatarUrl name } ... on Team { name slug } } } }
              comments(last: 60) { nodes { id author { login avatarUrl ... on User { name } } body createdAt url } }
              reviews(last: 30) { nodes { id author { login avatarUrl ... on User { name } } body submittedAt url } }
              reviewThreads(last: 50) { nodes { id path line isResolved comments(first: 20) { nodes { author { login avatarUrl ... on User { name } } body createdAt url } } } }
              latestReviews(first: 30) { nodes { state submittedAt author { login avatarUrl ... on User { name } } } }
              commits(first: 100) { totalCount nodes { commit {
                oid abbreviatedOid messageHeadline messageBody authoredDate url
                signature { isValid }
                author { name user { login avatarUrl name } }
                statusCheckRollup { state }
              } } }
              checks: commits(last: 1) { nodes { commit { statusCheckRollup { state contexts(first: 50) { nodes {
                __typename
                ... on CheckRun { id name status conclusion startedAt completedAt detailsUrl }
                ... on StatusContext { context state targetUrl createdAt description }
              } } } } } }
            }
          }
        }
        """
    // swiftlint:enable line_length
}

// MARK: - Response DTOs

struct DetailResponse: Decodable, Sendable {
    let viewer: Viewer?
    let repository: Repository?
    struct Viewer: Decodable, Sendable { let login: String }
    struct Repository: Decodable, Sendable {
        let pullRequest: DetailNode?
    }
}

struct DetailNode: Decodable, Sendable {
    let id: String?
    let viewerCanEnableAutoMerge, viewerCanMergeAsAdmin: Bool?
    let autoMergeRequest: AutoMergeNode?
    let number: Int
    let title: String
    let url: URL?
    let isDraft: Bool
    let createdAt: Date
    let updatedAt: Date
    let additions: Int
    let deletions: Int
    let changedFiles: Int
    let headRefName: String
    let baseRefName: String
    let headRefOid: String
    let baseRefOid: String
    let reviewDecision: String?
    let mergeable: String?
    let mergeStateStatus: String?
    let state: String
    let body: String
    let repository: RepositoryNode
    let headRepositoryOwner: LoginNode?
    let author: GitHubActorNode?
    let labels: Nodes<LabelNode>
    let assignees: Nodes<GitHubActorNode>
    let milestone: MilestoneNode?
    let closingIssuesReferences: Nodes<IssueNode>
    let reviewRequests: Nodes<ReviewRequestNode>
    let latestReviews: Nodes<ReviewNode>
    let commits: Nodes<CommitWrapper>
    let checks: Nodes<CheckCommitWrapper>
    let comments: Nodes<CommentNode>?
    let reviews: Nodes<CommentNode>?
    let reviewThreads: Nodes<ThreadNode>?

    /// An issue comment, review or review comment (`submittedAt` for reviews).
    struct CommentNode: Decodable, Sendable {
        let id: String?
        let author: GitHubActorNode?
        let body: String
        let createdAt: Date?
        let submittedAt: Date?
        let url: URL?
        var date: Date { createdAt ?? submittedAt ?? .distantPast }
    }

    struct ThreadNode: Decodable, Sendable {
        let id: String?
        let path: String
        let line: Int?
        let isResolved: Bool?
        let comments: Nodes<CommentNode>
    }

    /// Mentions of the viewer and their own participation, newest first.
    func involvement(of login: String) -> Involvement {
        var mentions: [Mention] = []
        func add(_ node: CommentNode, _ place: Mention.Place) {
            guard node.author?.login.lowercased() != login.lowercased(),
                let excerpt = MentionFinder.excerpt(mentioning: login, in: node.body)
            else { return }
            mentions.append(
                Mention(
                    place: place, author: node.author?.userRef ?? UserRef(login: "ghost"), date: node.date,
                    excerpt: excerpt, url: node.url))
        }
        if author?.login.lowercased() != login.lowercased(),
            let excerpt = MentionFinder.excerpt(mentioning: login, in: body)
        {
            mentions.append(
                Mention(
                    place: .description, author: author?.userRef ?? UserRef(login: "ghost"), date: createdAt,
                    excerpt: excerpt, url: url))
        }
        comments?.values.forEach { add($0, .comment) }
        reviews?.values.forEach { add($0, .review) }
        for thread in reviewThreads?.values ?? [] {
            thread.comments.values.forEach { add($0, .codeComment(path: thread.path, line: thread.line)) }
        }
        let own =
            (comments?.values ?? []) + (reviews?.values ?? [])
            + (reviewThreads?.values.flatMap(\.comments.values) ?? [])
        let mine = own.filter { $0.author?.login.lowercased() == login.lowercased() }
        let others = own.filter {
            guard let other = $0.author?.login.lowercased() else { return false }
            return other != login.lowercased() && !other.hasSuffix("[bot]")
        }
        let lastCommit = commits.values.map(\.commit.authoredDate).max()
        return Involvement(
            login: login, mentions: mentions.sorted { $0.date > $1.date }, ownCommentCount: mine.count,
            lastOwnCommentAt: mine.map(\.date).max(),
            othersLastActivityAt: (others.map(\.date) + [lastCommit].compactMap { $0 }).max())
    }

    struct Nodes<Element: Decodable & Sendable>: Decodable, Sendable {
        let nodes: [Element?]
        var values: [Element] { nodes.compactMap { $0 } }
    }

    struct RepositoryNode: Decodable, Sendable {
        let name: String
        let owner: LoginNode
        let viewerPermission: String?
        let viewerDefaultMergeMethod: String?
        let mergeCommitAllowed: Bool?
        let squashMergeAllowed: Bool?
        let rebaseMergeAllowed: Bool?
    }

    struct LoginNode: Decodable, Sendable { let login: String }
    struct LabelNode: Decodable, Sendable { let name: String; let color: String }
    struct MilestoneNode: Decodable, Sendable { let title: String }
    struct IssueNode: Decodable, Sendable { let number: Int; let title: String; let url: URL? }

    struct ReviewRequestNode: Decodable, Sendable {
        let asCodeOwner: Bool?
        let requestedReviewer: Reviewer?
        struct Reviewer: Decodable, Sendable {
            let typename: String
            let login: String?
            let avatarUrl: URL?
            let name: String?
            let slug: String?
            enum CodingKeys: String, CodingKey {
                case typename = "__typename", login, avatarUrl, name, slug
            }
        }
    }

    struct ReviewNode: Decodable, Sendable {
        let state: String
        let author: GitHubActorNode?
    }

    struct CommitWrapper: Decodable, Sendable {
        let commit: CommitNode
    }

    struct CommitNode: Decodable, Sendable {
        let oid: String
        let messageHeadline: String
        let messageBody: String
        let authoredDate: Date
        let url: URL?
        let signature: Signature?
        let author: GitActor?
        let statusCheckRollup: Rollup?

        struct Signature: Decodable, Sendable { let isValid: Bool }
        struct Rollup: Decodable, Sendable { let state: String }
        struct GitActor: Decodable, Sendable {
            let name: String?
            let user: GitHubActorNode?
        }
    }

    struct CheckCommitWrapper: Decodable, Sendable {
        let commit: CheckCommit
        struct CheckCommit: Decodable, Sendable {
            let statusCheckRollup: CheckRollup?
        }
        struct CheckRollup: Decodable, Sendable {
            let state: String
            let contexts: Nodes<CheckContext>
        }
    }

    struct CheckContext: Decodable, Sendable {
        let typename: String
        let id: String?
        let description: String?
        let name: String?
        let status: String?
        let conclusion: String?
        let startedAt: Date?
        let completedAt: Date?
        let detailsUrl: URL?
        let context: String?
        let state: String?
        let targetUrl: URL?

        enum CodingKeys: String, CodingKey {
            case typename = "__typename", id, description, name, status, conclusion, startedAt, completedAt
            case detailsUrl, context, state, targetUrl
        }

        var checkRun: PullRequestDetail.CheckRun? {
            if typename == "CheckRun", let name {
                let duration: Duration? = startedAt.flatMap { start in
                    completedAt.map { .seconds($0.timeIntervalSince(start)) }
                }
                return .init(
                    name: name, state: Self.state(status: status, conclusion: conclusion), duration: duration,
                    url: detailsUrl, nodeID: id)
            }
            if typename == "StatusContext", let context {
                let state = state.flatMap { CheckState(rawValue: $0.lowercased()) } ?? .none
                return .init(
                    name: context, state: state, duration: nil, url: targetUrl, statusDescription: description)
            }
            return nil
        }

        static func state(status: String?, conclusion: String?) -> CheckState {
            guard status == "COMPLETED" else { return .pending }
            switch conclusion {
            case "SUCCESS", "NEUTRAL", "SKIPPED": return .success
            case "FAILURE", "TIMED_OUT", "STARTUP_FAILURE", "ACTION_REQUIRED", "CANCELLED": return .failure
            default: return .none
            }
        }
    }

    // MARK: Mapping

    var detail: PullRequestDetail {
        // The head commit's rollup (`checks` = commits(last: 1)); `commits` is capped at the first 100.
        let checkState = checks.values.last?.commit.statusCheckRollup.flatMap {
            CheckState(rawValue: $0.state.lowercased())
        }
        let review = reviewDecision.flatMap(ReviewDecision.init(rawValue:)) ?? .none
        let summary = PullRequestSummary(
            id: PullRequestID(owner: repository.owner.login, repository: repository.name, number: number),
            title: title,
            author: author?.userRef ?? UserRef(login: "ghost"),
            url: url,
            isDraft: isDraft,
            createdAt: createdAt,
            updatedAt: updatedAt,
            additions: additions,
            deletions: deletions,
            headRefName: headRefName,
            baseRefName: baseRefName,
            checkState: checkState ?? .none,
            reviewDecision: review,
            mergeability: mergeable.flatMap(Mergeability.init(rawValue:)) ?? .unknown
        )
        let checkRuns = (checks.values.last?.commit.statusCheckRollup?.contexts.values ?? []).compactMap(\.checkRun)
            .sorted { lhs, rhs in lhs.state.sortOrder < rhs.state.sortOrder }
        let prState = PullRequestDetail.State(rawValue: state) ?? .open
        return PullRequestDetail(
            summary: summary,
            body: body,
            state: prState,
            headSHA: headRefOid,
            baseSHA: baseRefOid,
            headOwner: headRepositoryOwner?.login,
            changedFiles: changedFiles,
            labels: labels.values.map { .init(name: $0.name, color: $0.color) },
            assignees: assignees.values.map(\.userRef),
            milestone: milestone?.title,
            linkedIssues: closingIssuesReferences.values.map { .init(number: $0.number, title: $0.title, url: $0.url) },
            reviewers: reviewers,
            mergeStatus: .derive(
                state: prState, mergeStateStatus: mergeStateStatus, reviewDecision: review, checks: checkRuns,
                isDraft: isDraft),
            checks: checkRuns,
            commits: commits.values.map(\.commit.model)
        )
    }
}

extension DetailNode.CommitNode {
    var model: Commit {
        Commit(
            sha: oid,
            subject: messageHeadline,
            body: messageBody,
            author: author?.user?.userRef ?? UserRef(login: author?.name ?? "unknown", name: author?.name),
            authoredAt: authoredDate,
            isVerified: signature?.isValid ?? false,
            checkState: statusCheckRollup.flatMap { CheckState(rawValue: $0.state.lowercased()) } ?? .none,
            url: url
        )
    }
}

extension CheckState {
    /// Failing first, then running, then passing.
    var sortOrder: Int {
        switch self {
        case .failure, .error: 0
        case .pending, .expected: 1
        case .success: 2
        case .none: 3
        }
    }
}

extension DetailNode {
    /// Latest review per person plus pending requests (people and teams, code owners marked).
    fileprivate var reviewers: [PullRequestDetail.Reviewer] {
        var result: [PullRequestDetail.Reviewer] = latestReviews.values.compactMap { review in
            guard let author = review.author else { return nil }
            let status = PullRequestDetail.Reviewer.Status(rawValue: review.state) ?? .commented
            return .init(name: author.login, user: author.userRef, isTeam: false, status: status)
        }
        for request in reviewRequests.values {
            guard let reviewer = request.requestedReviewer else { continue }
            if reviewer.typename == "Team", let slug = reviewer.slug {
                result.append(
                    .init(
                        name: "@\(repository.owner.login)/\(slug)", user: nil, isTeam: true, status: .pending,
                        isCodeOwner: request.asCodeOwner ?? false))
            } else if let login = reviewer.login, !result.contains(where: { $0.name == login }) {
                let user = UserRef(login: login, name: reviewer.name, avatarURL: reviewer.avatarUrl)
                result.append(
                    .init(
                        name: login, user: user, isTeam: false, status: .pending,
                        isCodeOwner: request.asCodeOwner ?? false))
            }
        }
        return result
    }
}
