import Foundation

/// A locally installed AI agent CLI (see specs/architecture.md §8.1).
public protocol AgentProvider: Sendable {
    var name: String { get }
    /// `nil` if the agent is not installed.
    func detectVersion() async -> String?
    func review(_ request: ReviewRequest) async throws -> AgentReviewOutput
    /// One chat turn; `sessionID` continues an earlier conversation.
    func chat(_ request: ChatRequest) async throws -> ChatReply
    /// A read-only investigation with structured output (e.g. checking a deployment in logs and monitoring).
    func investigate(_ request: InvestigationRequest) async throws -> InvestigationReply
}

extension AgentProvider {
    public func investigate(_ request: InvestigationRequest) async throws -> InvestigationReply {
        throw AgentError.failed("\(name) cannot run investigations")
    }
}

/// A read-only task beyond the code: the agent may use what the user set up and allowed in their own agent
/// configuration (MCP servers such as a monitoring tool) plus the tools named here. Nothing is edited.
public struct InvestigationRequest: Sendable {
    public let prompt: String
    /// JSON schema of the answer.
    public let schema: String
    public let model: String
    public let effort: String
    public let language: String
    /// The repository checkout the agent may read (its guidelines name the tools to use).
    public let workingDirectory: URL?
    /// Permission rules allowed on top of the user's own, e.g. `Bash(gh run view:*)`.
    public let allowedTools: [String]

    public init(
        prompt: String, schema: String, model: String, effort: String, language: String, workingDirectory: URL?,
        allowedTools: [String] = []
    ) {
        self.prompt = prompt
        self.schema = schema
        self.model = model
        self.effort = effort
        self.language = language
        self.workingDirectory = workingDirectory
        self.allowedTools = allowedTools
    }
}

public struct InvestigationReply: Sendable {
    /// The answer as JSON matching the request's schema.
    public let json: Data
    public var tokens: TokenUsage?
    /// What the agent did, in order: one line per tool call ("Bash: gh run view 123 --log-failed").
    public var activity: [String]
    /// Tools the agent tried but its permission rules did not allow (full names), without repeats.
    public var deniedTools: [String] = []

    public init(json: Data, tokens: TokenUsage? = nil, activity: [String] = []) {
        self.json = json
        self.tokens = tokens
        self.activity = activity
    }
}

/// A chat turn (see specs/architecture.md §8.6).
public struct ChatRequest: Sendable {
    public let message: String
    public let sessionID: String?
    public let model: String
    public let language: String
    public let workingDirectory: URL?
    /// Reasoning effort (`nil`: the agent's default).
    public let effort: String?

    public init(
        message: String, sessionID: String?, model: String, effort: String? = nil, language: String,
        workingDirectory: URL?
    ) {
        self.message = message
        self.sessionID = sessionID
        self.model = model
        self.effort = effort
        self.language = language
        self.workingDirectory = workingDirectory
    }
}

public struct ChatReply: Sendable, Equatable {
    public let text: String
    public let sessionID: String?
    /// Tokens the turn used (`nil`: unknown).
    public var tokens: TokenUsage?

    public init(text: String, sessionID: String?, tokens: TokenUsage? = nil) {
        self.text = text
        self.sessionID = sessionID
        self.tokens = tokens
    }
}

public enum AgentError: Error, Equatable, Sendable {
    case notInstalled(String)
    case failed(String)
    case invalidOutput(String)
}
