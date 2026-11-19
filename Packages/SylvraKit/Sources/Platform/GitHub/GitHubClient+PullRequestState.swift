import Foundation
import SylvraCore

extension GitHubClient {
    /// Whether a pull request is still open (`nil`: the repository or pull request isn't visible to the token).
    public func isPullRequestOpen(_ id: PullRequestID) async throws -> Bool? {
        let response = try await graphQL(
            """
            query PullRequestState($owner: String!, $name: String!, $number: Int!) {
              repository(owner: $owner, name: $name) { pullRequest(number: $number) { state } }
            }
            """,
            variables: ["owner": .string(id.owner), "name": .string(id.repository), "number": .int(id.number)],
            as: PullRequestStateResponse.self)
        return response.repository?.pullRequest.map { $0.state == "OPEN" }
    }
}

private struct PullRequestStateResponse: Decodable, Sendable {
    struct Repository: Decodable, Sendable {
        struct PullRequest: Decodable, Sendable { let state: String }
        let pullRequest: PullRequest?
    }
    let repository: Repository?
}
