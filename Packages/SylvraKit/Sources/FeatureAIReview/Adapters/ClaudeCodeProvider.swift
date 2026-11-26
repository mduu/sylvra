import Foundation
import Platform

/// Runs reviews with the Claude Code CLI in print mode with structured output.
///
/// Isolation (the PR checkout is untrusted code): the agent runs in an empty Sylvra-owned directory and gets the
/// worktree only via `--add-dir`, loads only the user's settings (no project settings, hooks or MCP servers from the
/// PR), uses no MCP servers and only the read-only tools Read, Grep and Glob (`--permission-mode dontAsk`).
public struct ClaudeCodeProvider: AgentProvider {
    public let name = "Claude Code"
    let runner: any ProcessRunning
    /// Receives the subscription's limits Claude Code reports with every call.
    private let onUsage: (@Sendable (ClaudeUsage) -> Void)?

    public init(
        runner: any ProcessRunning = SystemProcessRunner(), onUsage: (@Sendable (ClaudeUsage) -> Void)? = nil
    ) {
        self.runner = runner
        self.onUsage = onUsage
    }

    /// A tiny Haiku call only to learn the subscription's limits (e.g. at launch, before any review or chat).
    public func probeUsage() async throws -> ClaudeUsage? {
        guard let claude = ExecutableLocator.locate("claude") else { throw AgentError.notInstalled(name) }
        let result = try await runner.run(
            claude, arguments: Self.probeArguments, workingDirectory: try Self.isolatedDirectory(),
            input: Data("Reply with: ok".utf8))
        let usage = ClaudeUsage.parse(streamJSON: result.standardOutput)
        if let usage { onUsage?(usage) }
        return usage
    }

    static let probeArguments =
        [
            "--print", "--output-format", "stream-json", "--verbose", "--model", "haiku", "--max-turns", "1",
            "--no-session-persistence",
        ] + isolationArguments(workspace: nil)

    /// Passes on the limits and returns the result line (stream-json prints one JSON object per line).
    func handle(_ result: ProcessResult) -> ProcessResult {
        if let usage = ClaudeUsage.parse(streamJSON: result.standardOutput) { onUsage?(usage) }
        return ProcessResult(
            exitCode: result.exitCode, standardOutput: Self.resultLine(of: result.standardOutput),
            standardError: result.standardError)
    }

    /// The final `result` message of stream-json output; other output (an error text) stays as it is.
    static func resultLine(of output: String) -> String {
        output.split(whereSeparator: \.isNewline).last { $0.hasPrefix("{") && $0.contains("\"type\":\"result\"") }
            .map(String.init) ?? output
    }

    public func detectVersion() async -> String? {
        try? await runner.output(of: "claude", arguments: ["--version"])
    }

    public func review(_ request: ReviewRequest) async throws -> AgentReviewOutput {
        guard let claude = ExecutableLocator.locate("claude") else { throw AgentError.notInstalled(name) }
        let result = try await runner.run(
            claude, arguments: Self.arguments(for: request), workingDirectory: try Self.isolatedDirectory(),
            input: Data(request.prompt.utf8))
        return try Self.decode(handle(result))
    }

    public func chat(_ request: ChatRequest) async throws -> ChatReply {
        guard let claude = ExecutableLocator.locate("claude") else { throw AgentError.notInstalled(name) }
        let result = handle(
            try await runner.run(
                claude, arguments: Self.chatArguments(for: request), workingDirectory: try Self.isolatedDirectory(),
                input: Data(request.message.utf8)))
        guard let data = result.standardOutput.data(using: .utf8),
            let envelope = try? JSONDecoder().decode(ChatEnvelope.self, from: data), let text = envelope.result
        else {
            throw AgentError.failed(
                (result.standardError.isEmpty ? result.standardOutput : result.standardError)
                    .trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return ChatReply(text: text, sessionID: envelope.sessionID ?? request.sessionID, tokens: envelope.usage)
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

    /// The chat answers a reviewer between two lines of code: the point first, as short as the question allows.
    static func chatSystemPrompt(language: String) -> String {
        """
        You are a code review assistant inside Sylvra. Never modify files. Answer in \(language).
        Be brief: lead with the answer in the first sentence, no preamble, no restating the question, no summary \
        at the end. Usually 1–4 sentences or a few short bullets; go longer only when the reviewer asks for detail \
        or the answer truly needs it. Show code only when it is the answer, and only the lines that matter.
        Reference code as path:line so the reviewer can jump there.
        """
    }

    static func chatArguments(for request: ChatRequest) -> [String] {
        var arguments = [
            "--print", "--output-format", "stream-json", "--verbose", "--model", request.model,
            "--append-system-prompt", chatSystemPrompt(language: request.language),
        ]
        if let effort = request.effort { arguments += ["--effort", effort] }
        arguments += isolationArguments(workspace: request.workingDirectory)
        if let session = request.sessionID { arguments += ["--resume", session] }
        return arguments
    }

    private struct ChatEnvelope: Decodable {
        let result: String?
        let sessionID: String?
        let usage: TokenUsage?
        enum CodingKeys: String, CodingKey {
            case result, usage
            case sessionID = "session_id"
        }
    }

    static func arguments(for request: ReviewRequest) -> [String] {
        [
            "--print",
            "--output-format", "stream-json", "--verbose",
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
        if var output = envelope.structuredOutput {
            output.tokens = envelope.usage
            return output
        }
        // Fallback: the result text itself may be the JSON object.
        if let text = envelope.result, let json = text.data(using: .utf8),
            var output = try? JSONDecoder().decode(AgentReviewOutput.self, from: json)
        {
            output.tokens = envelope.usage
            return output
        }
        throw AgentError.invalidOutput(String((envelope.result ?? "").prefix(300)))
    }

    private struct Envelope: Decodable {
        let result: String?
        let structuredOutput: AgentReviewOutput?
        let usage: TokenUsage?
        enum CodingKeys: String, CodingKey {
            case result, usage
            case structuredOutput = "structured_output"
        }
    }
}
