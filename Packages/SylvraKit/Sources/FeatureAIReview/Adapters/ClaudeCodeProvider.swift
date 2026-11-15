import Foundation
import Platform

/// Runs reviews with the Claude Code CLI in print mode with structured output.
///
/// The agent gets read-only tools (Read, Grep, Glob) and runs in the PR worktree when available.
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
        let workingDirectory = request.workingDirectory ?? FileManager.default.temporaryDirectory
        let result = try await runner.run(
            claude, arguments: Self.arguments(for: request), workingDirectory: workingDirectory,
            input: Data(request.prompt.utf8))
        return try Self.decode(result)
    }

    static func arguments(for request: ReviewRequest) -> [String] {
        [
            "--print",
            "--output-format", "json",
            "--json-schema", ReviewRequest.outputSchema,
            "--model", request.model,
            "--effort", request.effort,
            "--tools", "Read", "Grep", "Glob",
            "--no-session-persistence",
            "--append-system-prompt",
            "You are running inside Sylvra, a code review app. Never modify files. Answer in \(request.language).",
        ]
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
