import Foundation
import Platform
import SylvraCore

/// Stacks: GitHub's own (`PullRequest.stack`, still a preview API) and, when the pull request isn't in one, a
/// stack derived from branches. The stack fields live in their own query: should GitHub rename them, or a GitHub
/// Enterprise Server not know them, only the stack goes missing, never the pull request.
extension GitHubPullRequestDetailLoader {
    public func loadStack(for detail: PullRequestDetail) async throws -> StackStatus? {
        let id = detail.summary.id
        let current = PullRequestStack.Entry(summary: detail.summary, state: detail.state, headSHA: detail.headSHA)
        let native = try? await loadGitHubStack(for: id)
        var stack = native?.stack
        if stack == nil, detail.state == .open {
            var defaultBranch = native?.defaultBranch
            if native == nil { defaultBranch = try? await loadDefaultBranch(of: id) }
            stack = try await walker(for: id, defaultBranch: defaultBranch).stack(around: current)
        }
        guard let stack, stack.index(of: id) != nil else { return nil }
        var status = StackStatus(stack: stack, current: id)
        if let parent = status.parent, parent.state == .open, detail.state == .open {
            status.commitsBehindParent = try? await commitsMissing(
                from: parent.summary.headRefName, in: detail.summary.headRefName, of: id)
        }
        return status
    }

    private func loadGitHubStack(for id: PullRequestID) async throws -> (
        stack: PullRequestStack?, defaultBranch: String?
    ) {
        let response = try await client.graphQL(
            Self.stackQuery, variables: Self.variables(id), as: StackResponse.self)
        let repository = response.repository
        guard let stack = repository?.pullRequest?.stack else { return (nil, repository?.defaultBranchRef?.name) }
        let nodes = stack.entries.nodes.compactMap { $0 }
        let entries = nodes.compactMap { $0.pullRequest?.entry }
        let positions = Dictionary(
            nodes.compactMap { node in node.pullRequest.map { ($0.entry.id, node.position) } },
            uniquingKeysWith: { first, _ in first })
        let ordered = PullRequestStack.ordered(entries, positions: positions)
        return (
            PullRequestStack(source: .gitHub, trunk: stack.baseRefName, entries: ordered),
            repository?.defaultBranchRef?.name
        )
    }

    private func loadDefaultBranch(of id: PullRequestID) async throws -> String? {
        let response = try await client.graphQL(
            """
            query($owner: String!, $name: String!) {
              repository(owner: $owner, name: $name) { defaultBranchRef { name } }
            }
            """,
            variables: ["owner": .string(id.owner), "name": .string(id.repository)], as: StackResponse.self)
        return response.repository?.defaultBranchRef?.name
    }

    private func walker(for id: PullRequestID, defaultBranch: String?) -> BranchStackWalker {
        let client = client
        return BranchStackWalker(
            pullRequestsWithHead: { try await Self.openPullRequests(field: "headRefName", branch: $0, of: id, client) },
            pullRequestsWithBase: { try await Self.openPullRequests(field: "baseRefName", branch: $0, of: id, client) },
            defaultBranch: defaultBranch)
    }

    /// Open pull requests of the repository itself (forks excluded) by head or base branch.
    private static func openPullRequests(
        field: String, branch: String, of id: PullRequestID, _ client: GitHubClient
    ) async throws -> [PullRequestStack.Entry] {
        let response = try await client.graphQL(
            branchQuery(field: field),
            variables: ["owner": .string(id.owner), "name": .string(id.repository), "branch": .string(branch)],
            as: BranchResponse.self)
        return (response.repository?.pullRequests.nodes ?? []).compactMap { node in
            guard let node, node.isCrossRepository != true else { return nil }
            return node.entry
        }
    }

    /// Commits on `parent` that `branch` doesn't contain.
    private func commitsMissing(from parent: String, in branch: String, of id: PullRequestID) async throws -> Int? {
        let response = try await client.graphQL(
            """
            query($owner: String!, $name: String!, $branch: String!, $parent: String!) {
              repository(owner: $owner, name: $name) {
                ref(qualifiedName: $branch) { compare(headRef: $parent) { aheadBy } }
              }
            }
            """,
            variables: [
                "owner": .string(id.owner), "name": .string(id.repository),
                "branch": .string("refs/heads/\(branch)"), "parent": .string(parent),
            ],
            as: CompareResponse.self)
        return response.repository?.ref?.compare?.aheadBy
    }

    private static func variables(_ id: PullRequestID) -> [String: GraphQLValue] {
        ["owner": .string(id.owner), "name": .string(id.repository), "number": .int(id.number)]
    }

    static let stackQuery = """
        query($owner: String!, $name: String!, $number: Int!) {
          repository(owner: $owner, name: $name) {
            defaultBranchRef { name }
            pullRequest(number: $number) {
              stack { baseRefName entries(first: 30) { nodes { position pullRequest { ...StackPR } } } }
            }
          }
        }
        """ + StackPullRequestNode.fragment

    /// `field` is `headRefName` or `baseRefName` (fixed in code, never user data).
    static func branchQuery(field: String) -> String {
        """
        query($owner: String!, $name: String!, $branch: String!) {
          repository(owner: $owner, name: $name) {
            pullRequests(\(field): $branch, states: [OPEN], first: 5) { nodes { ...StackPR isCrossRepository } }
          }
        }
        """ + StackPullRequestNode.fragment
    }
}

// MARK: - Response DTOs

private struct StackResponse: Decodable, Sendable {
    let repository: Repository?
    struct Repository: Decodable, Sendable {
        let defaultBranchRef: Ref?
        let pullRequest: PullRequest?
    }
    struct Ref: Decodable, Sendable { let name: String }
    struct PullRequest: Decodable, Sendable { let stack: Stack? }
    struct Stack: Decodable, Sendable {
        let baseRefName: String
        let entries: DetailNode.Nodes<Entry>
    }
    struct Entry: Decodable, Sendable {
        let position: Int
        let pullRequest: StackPullRequestNode?
    }
}

private struct BranchResponse: Decodable, Sendable {
    let repository: Repository?
    struct Repository: Decodable, Sendable { let pullRequests: DetailNode.Nodes<StackPullRequestNode> }
}

private struct CompareResponse: Decodable, Sendable {
    let repository: Repository?
    struct Repository: Decodable, Sendable { let ref: Ref? }
    struct Ref: Decodable, Sendable { let compare: Comparison? }
    struct Comparison: Decodable, Sendable { let aheadBy: Int }
}

/// A layer of a stack: enough to list it and to open it.
struct StackPullRequestNode: Decodable, Sendable {
    static let fragment = """

        fragment StackPR on PullRequest {
          number title url isDraft createdAt updatedAt additions deletions
          headRefName baseRefName headRefOid state
          repository { name owner { login } }
          author { login avatarUrl ... on User { name } }
        }
        """

    let number: Int
    let title: String
    let url: URL?
    let isDraft: Bool
    let createdAt: Date
    let updatedAt: Date
    let additions: Int
    let deletions: Int
    let headRefName: String
    let baseRefName: String
    let headRefOid: String?
    let state: String
    let repository: DetailNode.RepositoryNode
    let author: GitHubActorNode?
    let isCrossRepository: Bool?

    var entry: PullRequestStack.Entry {
        let summary = PullRequestSummary(
            id: PullRequestID(owner: repository.owner.login, repository: repository.name, number: number),
            title: title, author: author?.userRef ?? UserRef(login: "ghost"), url: url, isDraft: isDraft,
            createdAt: createdAt, updatedAt: updatedAt, additions: additions, deletions: deletions,
            headRefName: headRefName, baseRefName: baseRefName)
        return PullRequestStack.Entry(
            summary: summary, state: PullRequestDetail.State(rawValue: state) ?? .open, headSHA: headRefOid)
    }
}
