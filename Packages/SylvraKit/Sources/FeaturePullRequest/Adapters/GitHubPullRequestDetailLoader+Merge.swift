import Foundation
import Platform
import SylvraCore

extension DetailNode {
    struct AutoMergeNode: Decodable, Sendable { let mergeMethod: String? }

    /// The merge methods the repository allows and what the viewer may do (`nil` without the node ID).
    var mergeOptions: MergeOptions? {
        guard let id else { return nil }
        var methods: [MergeMethod] = []
        if repository.mergeCommitAllowed == true { methods.append(.merge) }
        if repository.squashMergeAllowed == true { methods.append(.squash) }
        if repository.rebaseMergeAllowed == true { methods.append(.rebase) }
        // GitHub's default for the viewer (their last choice in the repository) leads.
        if let preferred = repository.viewerDefaultMergeMethod.flatMap(MergeMethod.init(rawValue:)),
            let index = methods.firstIndex(of: preferred)
        {
            methods.insert(methods.remove(at: index), at: 0)
        }
        return MergeOptions(
            pullRequestNodeID: id, methods: methods,
            viewerCanMerge: ["WRITE", "MAINTAIN", "ADMIN"].contains(repository.viewerPermission ?? ""),
            viewerCanEnableAutoMerge: viewerCanEnableAutoMerge ?? false,
            viewerCanBypassRules: viewerCanMergeAsAdmin ?? false,
            autoMerge: autoMergeRequest?.mergeMethod.flatMap(MergeMethod.init(rawValue:)))
    }
}

extension GitHubPullRequestDetailLoader: PullRequestMerging {
    /// `expectedHeadOid`: GitHub refuses when commits were pushed after the reviewer last saw the pull request.
    public func merge(_ options: MergeOptions, method: MergeMethod, expectedHeadSHA: String) async throws {
        _ = try await client.graphQL(
            """
            mutation($id: ID!, $method: PullRequestMergeMethod!, $head: GitObjectID!) {
              mergePullRequest(input: {pullRequestId: $id, mergeMethod: $method, expectedHeadOid: $head}) {
                clientMutationId
              }
            }
            """,
            variables: [
                "id": .string(options.pullRequestNodeID), "method": .string(method.rawValue),
                "head": .string(expectedHeadSHA),
            ],
            as: MutationAnswer.self)
    }

    public func enableAutoMerge(_ options: MergeOptions, method: MergeMethod) async throws {
        _ = try await client.graphQL(
            """
            mutation($id: ID!, $method: PullRequestMergeMethod!) {
              enablePullRequestAutoMerge(input: {pullRequestId: $id, mergeMethod: $method}) { clientMutationId }
            }
            """,
            variables: ["id": .string(options.pullRequestNodeID), "method": .string(method.rawValue)],
            as: MutationAnswer.self)
    }

    public func disableAutoMerge(_ options: MergeOptions) async throws {
        _ = try await client.graphQL(
            """
            mutation($id: ID!) {
              disablePullRequestAutoMerge(input: {pullRequestId: $id}) { clientMutationId }
            }
            """,
            variables: ["id": .string(options.pullRequestNodeID)], as: MutationAnswer.self)
    }
}

/// The mutations' answers carry nothing Sylvra needs: the pull request is reloaded afterwards.
private struct MutationAnswer: Decodable, Sendable {}
