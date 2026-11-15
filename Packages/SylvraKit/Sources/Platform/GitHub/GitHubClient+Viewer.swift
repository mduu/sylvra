import Foundation
import SylvraCore

extension GitHubClient {
    /// The signed-in user.
    public func viewer() async throws -> UserRef {
        let response = try await graphQL(
            "query { viewer { login name avatarUrl } }",
            as: ViewerResponse.self
        )
        return response.viewer.userRef
    }
}

/// GraphQL `Actor` / `User` fields shared by many queries.
public struct GitHubActorNode: Decodable, Sendable, Equatable {
    public let login: String
    public let name: String?
    public let avatarUrl: URL?

    public var userRef: UserRef { UserRef(login: login, name: name, avatarURL: avatarUrl) }
}

private struct ViewerResponse: Decodable, Sendable {
    let viewer: GitHubActorNode
}
