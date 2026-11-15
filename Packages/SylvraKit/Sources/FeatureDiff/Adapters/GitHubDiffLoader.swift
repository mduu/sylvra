import Foundation
import Platform
import SylvraCore

/// Loads the PR diff via REST and the viewed state via GraphQL.
public struct GitHubDiffLoader: DiffLoading {
    private let client: GitHubClient

    public init(client: GitHubClient) {
        self.client = client
    }

    public func loadDiff(for id: PullRequestID) async throws -> PullRequestDiff {
        async let diffData = client.rest(
            path: "repos/\(id.owner)/\(id.repository)/pulls/\(id.number)", accept: "application/vnd.github.v3.diff")
        async let viewed = client.graphQL(
            """
            query($owner: String!, $name: String!, $number: Int!) {
              repository(owner: $owner, name: $name) {
                pullRequest(number: $number) { id files(first: 100) { nodes { path viewerViewedState } } }
              }
            }
            """,
            variables: ["owner": .string(id.owner), "name": .string(id.repository), "number": .int(id.number)],
            as: ViewedResponse.self
        )
        let text = String(bytes: try await diffData, encoding: .utf8) ?? ""
        let pullRequest = try await viewed.repository?.pullRequest
        let viewedPaths = Set(
            pullRequest?.files?.nodes.compactMap { $0?.viewerViewedState == "VIEWED" ? $0?.path : nil } ?? [])
        return PullRequestDiff(files: UnifiedDiffParser.parse(text), viewedPaths: viewedPaths, nodeID: pullRequest?.id)
    }

    public func loadFileContent(for id: PullRequestID, path: String, ref: String) async throws -> String {
        let encodedPath = path.split(separator: "/").map {
            $0.addingPercentEncoding(withAllowedCharacters: .urlPathAllowed) ?? String($0)
        }.joined(separator: "/")
        let data = try await client.rest(
            path: "repos/\(id.owner)/\(id.repository)/contents/\(encodedPath)?ref=\(ref)",
            accept: "application/vnd.github.raw+json")
        return String(bytes: data, encoding: .utf8) ?? ""
    }

    public func setViewed(_ viewed: Bool, path: String, pullRequestNodeID: String) async throws {
        let mutation = viewed ? "markFileAsViewed" : "unmarkFileAsViewed"
        _ = try await client.graphQL(
            """
            mutation($id: ID!, $path: String!) {
              \(mutation)(input: { pullRequestId: $id, path: $path }) { clientMutationId }
            }
            """,
            variables: ["id": .string(pullRequestNodeID), "path": .string(path)],
            as: MutationResponse.self
        )
    }
}

private struct ViewedResponse: Decodable, Sendable {
    let repository: Repository?
    struct Repository: Decodable, Sendable { let pullRequest: PullRequest? }
    struct PullRequest: Decodable, Sendable {
        let id: String
        let files: Files?
    }
    struct Files: Decodable, Sendable { let nodes: [File?] }
    struct File: Decodable, Sendable {
        let path: String
        let viewerViewedState: String
    }
}

private struct MutationResponse: Decodable, Sendable {}
