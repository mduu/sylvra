import Foundation

/// A locally installed AI agent CLI (see specs/architecture.md §8.1).
public protocol AgentProvider: Sendable {
    var name: String { get }
    /// `nil` if the agent is not installed.
    func detectVersion() async -> String?
    func review(_ request: ReviewRequest) async throws -> AgentReviewOutput
    /// One chat turn; `sessionID` continues an earlier conversation.
    func chat(_ request: ChatRequest) async throws -> ChatReply
}

/// A chat turn (see specs/architecture.md §8.6).
public struct ChatRequest: Sendable {
    public let message: String
    public let sessionID: String?
    public let model: String
    public let language: String
    public let workingDirectory: URL?

    public init(message: String, sessionID: String?, model: String, language: String, workingDirectory: URL?) {
        self.message = message
        self.sessionID = sessionID
        self.model = model
        self.language = language
        self.workingDirectory = workingDirectory
    }
}

public struct ChatReply: Sendable, Equatable {
    public let text: String
    public let sessionID: String?

    public init(text: String, sessionID: String?) {
        self.text = text
        self.sessionID = sessionID
    }
}

public enum AgentError: Error, Equatable, Sendable {
    case notInstalled(String)
    case failed(String)
    case invalidOutput(String)
}
