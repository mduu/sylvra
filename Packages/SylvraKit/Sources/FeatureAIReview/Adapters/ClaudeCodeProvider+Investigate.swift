import Foundation
import Platform

extension ClaudeCodeProvider {
    /// Runs a read-only investigation. Unlike a review, the agent sees the user's own MCP servers (no
    /// `--strict-mcp-config`) — that is where monitoring tools live. `--permission-mode dontAsk` still denies
    /// every tool call the user has not allowed in their own Claude Code settings or the request names, and
    /// the built-in tools are limited to reading (and Bash only for the request's rules).
    public func investigate(_ request: InvestigationRequest) async throws -> InvestigationReply {
        guard let claude = ExecutableLocator.locate("claude") else { throw AgentError.notInstalled(name) }
        let raw = try await runner.run(
            claude, arguments: Self.investigationArguments(for: request),
            workingDirectory: try Self.isolatedDirectory(), input: Data(request.prompt.utf8))
        var reply = try Self.decodeInvestigation(handle(raw))
        reply.activity = Self.toolCalls(in: raw.standardOutput)
        return reply
    }

    /// The tool calls in stream-json output, one line each: the tool and what it was called with.
    static func toolCalls(in output: String) -> [String] {
        output.split(whereSeparator: \.isNewline).flatMap { line -> [String] in
            guard line.contains("\"tool_use\""), let data = line.data(using: .utf8),
                let event = try? JSONSerialization.jsonObject(with: data) as? [String: Any],
                let message = event["message"] as? [String: Any],
                let content = message["content"] as? [[String: Any]]
            else { return [] }
            return content.compactMap { part -> String? in
                guard part["type"] as? String == "tool_use", let name = part["name"] as? String else { return nil }
                let input = part["input"] as? [String: Any] ?? [:]
                let detail =
                    ["command", "query", "pattern", "file_path", "path", "description"].lazy
                    .compactMap { input[$0] as? String }.first
                    ?? (try? JSONSerialization.data(withJSONObject: input, options: [.sortedKeys]))
                    .map { String(decoding: $0, as: UTF8.self) } ?? ""
                let tool =
                    name.hasPrefix("mcp__") ? name.dropFirst(5).replacingOccurrences(of: "__", with: " · ") : name
                return detail.isEmpty ? tool : "\(tool): \(detail.prefix(300))"
            }
        }
    }

    static func investigationArguments(for request: InvestigationRequest) -> [String] {
        let usesShell = request.allowedTools.contains { $0.hasPrefix("Bash(") }
        var arguments = [
            "--print", "--output-format", "stream-json", "--verbose",
            "--json-schema", request.schema,
            "--model", request.model,
            "--effort", request.effort,
            "--no-session-persistence",
            "--append-system-prompt",
            """
            You are running inside Sylvra and investigate a deployment. You only read: never modify files, \
            configuration, infrastructure, monitors, tickets or anything else, and never trigger deployments or \
            restarts. If a tool call is denied, do not try another way around it; report the point as not \
            checked. Answer in \(request.language).
            """,
            "--tools", "Read", "Grep", "Glob",
        ]
        if usesShell { arguments.append("Bash") }
        arguments += ["--permission-mode", "dontAsk", "--setting-sources", "user"]
        if !request.allowedTools.isEmpty { arguments += ["--allowedTools"] + request.allowedTools }
        if let workspace = request.workingDirectory { arguments += ["--add-dir", workspace.path] }
        return arguments
    }

    /// The `structured_output` of the result line as JSON data (or the result text when it is the JSON).
    static func decodeInvestigation(_ result: ProcessResult) throws -> InvestigationReply {
        guard let data = result.standardOutput.data(using: .utf8),
            let envelope = try? JSONSerialization.jsonObject(with: data) as? [String: Any]
        else {
            let message =
                result.standardError.isEmpty ? String(result.standardOutput.prefix(300)) : result.standardError
            throw AgentError.failed(message.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        let tokens = (envelope["usage"]).flatMap { try? JSONSerialization.data(withJSONObject: $0) }
            .flatMap { try? JSONDecoder().decode(TokenUsage.self, from: $0) }
        if let output = envelope["structured_output"] as? [String: Any],
            let json = try? JSONSerialization.data(withJSONObject: output)
        {
            return InvestigationReply(json: json, tokens: tokens)
        }
        if let text = envelope["result"] as? String, let start = text.firstIndex(of: "{"),
            let end = text.lastIndex(of: "}"), start < end
        {
            return InvestigationReply(json: Data(text[start...end].utf8), tokens: tokens)
        }
        throw AgentError.invalidOutput(String(((envelope["result"] as? String) ?? "").prefix(300)))
    }
}
