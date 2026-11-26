import Foundation
import Platform
import Testing

@testable import FeatureAIReview

/// Investigations read beyond the code (monitoring), with the user's own agent setup — but only read.
struct InvestigationTests {
    private let request = InvestigationRequest(
        prompt: "Check prod", schema: "{}", model: "sonnet", effort: "medium", language: "German",
        workingDirectory: URL(fileURLWithPath: "/tmp/worktree"), allowedTools: ["Bash(gh run view:*)"])

    @Test func runsReadOnlyWithTheUsersOwnToolsAndPermissions() {
        let arguments = ClaudeCodeProvider.investigationArguments(for: request)
        // Only what the user allowed in their settings or the request names runs; nothing is asked or edited.
        #expect(arguments.contains("dontAsk"))
        #expect(!arguments.contains("Edit") && !arguments.contains("Write"))
        #expect(arguments.contains("Bash") && arguments.contains("Bash(gh run view:*)"))
        // The user's MCP servers (monitoring) stay available, unlike in a review.
        #expect(!arguments.contains("--strict-mcp-config"))
        #expect(ClaudeCodeProvider.isolationArguments(workspace: nil).contains("--strict-mcp-config"))
        // No settings, hooks or permissions from the repository.
        #expect(arguments.firstIndex(of: "--setting-sources").map { arguments[$0 + 1] } == "user")
        #expect(arguments.suffix(2) == ["--add-dir", "/tmp/worktree"])
    }

    @Test func noShellWithoutAShellRule() {
        let plain = InvestigationRequest(
            prompt: "", schema: "{}", model: "sonnet", effort: "low", language: "English", workingDirectory: nil)
        let arguments = ClaudeCodeProvider.investigationArguments(for: plain)
        #expect(!arguments.contains("Bash") && !arguments.contains("--allowedTools"))
    }

    @Test func readsTheStructuredAnswer() throws {
        let line =
            #"{"type":"result","result":"done","structured_output":{"verdict":"healthy"},"usage":{"input_tokens":10,"output_tokens":5}}"#
        let reply = try ClaudeCodeProvider.decodeInvestigation(
            ProcessResult(exitCode: 0, standardOutput: line, standardError: ""))
        let object = try JSONSerialization.jsonObject(with: reply.json) as? [String: String]
        #expect(object == ["verdict": "healthy"])

        let text = #"{"type":"result","result":"Here: {\"verdict\":\"problems\"}"}"#
        let fallback = try ClaudeCodeProvider.decodeInvestigation(
            ProcessResult(exitCode: 0, standardOutput: text, standardError: ""))
        #expect(String(decoding: fallback.json, as: UTF8.self) == #"{"verdict":"problems"}"#)
        #expect(throws: AgentError.self) {
            try ClaudeCodeProvider.decodeInvestigation(
                ProcessResult(exitCode: 1, standardOutput: "", standardError: "not logged in"))
        }
    }
}
