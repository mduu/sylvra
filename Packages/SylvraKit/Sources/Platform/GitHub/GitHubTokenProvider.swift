import Foundation

/// Supplies a GitHub access token.
public protocol GitHubTokenProviding: Sendable {
    /// Returns a token, or `nil` if the user is not signed in.
    func token() async throws -> String?
}

/// Reads the token of the GitHub CLI (`gh auth token`).
///
/// This is the first sign-in option (see specs/architecture.md §5): no extra login is needed
/// when the reviewer already uses `gh`.
public struct GitHubCLITokenProvider: GitHubTokenProviding {
    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning = SystemProcessRunner()) {
        self.runner = runner
    }

    public func token() async throws -> String? {
        guard ExecutableLocator.locate("gh") != nil else { return nil }
        do {
            let token = try await runner.output(of: "gh", arguments: ["auth", "token"])
            return token.isEmpty ? nil : token
        } catch ProcessRunnerError.failed {
            return nil  // gh installed, but not logged in
        }
    }
}

/// A fixed token (tests, previews).
public struct StaticTokenProvider: GitHubTokenProviding {
    private let value: String?

    public init(_ value: String?) {
        self.value = value
    }

    public func token() async throws -> String? { value }
}
