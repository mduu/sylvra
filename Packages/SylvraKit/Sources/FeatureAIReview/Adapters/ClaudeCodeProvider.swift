import Foundation
import Platform

/// Runs reviews with the Claude Code CLI in print mode with structured output.
///
/// Isolation (the PR checkout is untrusted code): the agent runs in an empty Sylvra-owned directory and gets the
/// worktree only via `--add-dir`, loads only the user's settings (no project settings, hooks or MCP servers from the
/// PR), uses no MCP servers and only the read-only tools Read, Grep and Glob (`--permission-mode dontAsk`).
public struct ClaudeCodeProvider: AgentProvider {
    public let name = "Claude Code"
    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning = SystemProcessRunner()) {
        self.runner = runner
    }

    public func detectVersion() async -> String? {
        try? await runner.output(of: "claude", arguments: ["--version"])
    }

    public func review(_ request: ReviewRequest) async throws -> AgentReviewOutput {
        guard let claude = ExecutableLocator.locate("claude") else { throw AgentError.notInstalled(name) }
        let result = try await runner.run(
            claude, arguments: Self.arguments(for: request), workingDirectory: try Self.isolatedDirectory(),
            input: Data(request.prompt.utf8))
        return try Self.decode(result)
    }

    public func chat(_ request: ChatRequest) async throws -> ChatReply {
        guard let claude = ExecutableLocator.locate("claude") else { throw AgentError.notInstalled(name) }
        let result = try await runner.run(
            claude, arguments: Self.chatArguments(for: request), workingDirectory: try Self.isolatedDirectory(),
            input: Data(request.message.utf8))
        guard let data = result.standardOutput.data(using: .utf8),
            let envelope = try? JSONDecoder().decode(ChatEnvelope.self, from: data), let text = envelope.result
        else {
            throw AgentError.failed(
                (result.standardError.isEmpty ? result.standardOutput : result.standardError)
                    .trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return ChatReply(text: text, sessionID: envelope.sessionID ?? request.sessionID)
    }

    /// Flags that keep the agent read-only and independent of configuration inside the PR.
    static func isolationArguments(workspace: URL?) -> [String] {
        var arguments = [
            "--tools", "Read", "Grep", "Glob",
            "--permission-mode", "dontAsk",
            "--setting-sources", "user",
            "--strict-mcp-config",
        ]
        if let workspace { arguments += ["--add-dir", workspace.path] }
        return arguments
    }

    /// Empty working directory owned by Sylvra (never the untrusted checkout).
    static func isolatedDirectory() throws -> URL {
        let directory = FileManager.default.temporaryDirectory.appending(
            path: "Sylvra-agent", directoryHint: .isDirectory)
        try FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        return directory
    }

    static func chatArguments(for request: ChatRequest) -> [String] {
        var arguments = [
            "--print", "--output-format", "json", "--model", request.model,
            "--append-system-prompt",
            "You are a code review assistant inside Sylvra. Never modify files. Answer concisely in \(request.language). "
                + "Reference code as path:line so the reviewer can jump there.",
        ]
        if let effort = request.effort { arguments += ["--effort", effort] }
        arguments += isolationArguments(workspace: request.workingDirectory)
        if let session = request.sessionID { arguments += ["--resume", session] }
        return arguments
    }

    private struct ChatEnvelope: Decodable {
        let result: String?
        let sessionID: String?
        enum CodingKeys: String, CodingKey {
            case result
            case sessionID = "session_id"
        }
    }

    static func arguments(for request: ReviewRequest) -> [String] {
        [
            "--print",
            "--output-format", "json",
            "--json-schema", ReviewRequest.outputSchema,
            "--model", request.model,
            "--effort", request.effort,
            "--no-session-persistence",
            "--append-system-prompt",
            "You are running inside Sylvra, a code review app. Never modify files. Answer in \(request.language).",
        ] + isolationArguments(workspace: request.workingDirectory)
    }

    static func decode(_ result: ProcessResult) throws -> AgentReviewOutput {
        guard let data = result.standardOutput.data(using: .utf8),
            let envelope = try? JSONDecoder().decode(Envelope.self, from: data)
        else {
            let message =
                result.standardError.isEmpty ? String(result.standardOutput.prefix(300)) : result.standardError
            throw AgentError.failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        if let output = envelope.structuredOutput { return output }
        // Fallback: the result text itself may be the JSON object.
        if let text = envelope.result, let json = text.data(using: .utf8),
            let output = try? JSONDecoder().decode(AgentReviewOutput.self, from: json)
        {
            return output
        }
        throw AgentError.invalidOutput(String((envelope.result ?? "").prefix(300)))
    }

    private struct Envelope: Decodable {
        let result: String?
        let structuredOutput: AgentReviewOutput?
        enum CodingKeys: String, CodingKey {
            case result
            case structuredOutput = "structured_output"
        }
    }
}
