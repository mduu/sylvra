import Foundation

/// A locally installed AI agent CLI (see specs/architecture.md §8.1).
public protocol AgentProvider: Sendable {
    var name: String { get }
    /// `nil` if the agent is not installed.
    func detectVersion() async -> String?
    func review(_ request: ReviewRequest) async throws -> AgentReviewOutput
}

public enum AgentError: Error, Equatable, Sendable {
    case notInstalled(String)
    case failed(String)
    case invalidOutput(String)
}
