import FeatureAIReview
import FeatureDelivery
import FeatureTerminal
import Foundation
import SylvraCore

/// Checks a delivery stage with the AI agent (composition: `FeatureDelivery` knows what to ask,
/// `FeatureAIReview` how to run an agent). The agent reads the repository's worktree for its guidelines and may
/// use the monitoring tools the user set up and allowed in their own agent configuration — reading only.
struct AgentDeliveryVerifier: DeliveryVerifying {
    let provider: any AgentProvider
    /// Model, effort and language: the AI review's defaults.
    let settings: @MainActor @Sendable () -> ReviewSettings
    let workspace: @Sendable (PullRequestID) async throws -> URL?

    func verify(_ request: VerificationRequest) async throws -> StageVerification {
        let settings = await settings()
        // A missing worktree is no reason to give up: the agent then works without the repository's guidelines.
        let directory = try? await workspace(request.pullRequest)
        do {
            let reply = try await provider.investigate(
                InvestigationRequest(
                    prompt: VerificationPrompt.prompt(for: request), schema: VerificationPrompt.schema,
                    model: settings.models.first ?? "sonnet", effort: settings.effort,
                    language: settings.agentLanguage, workingDirectory: directory,
                    allowedTools: VerificationPrompt.allowedTools + request.allowedTools))
            return try VerificationPrompt.decode(
                reply.json, for: request, activity: reply.activity, deniedTools: reply.deniedTools)
        } catch let error as AgentError {
            throw Failure(message: Self.message(for: error))
        } catch is DecodingError {
            throw Failure(message: String(localized: "The agent's answer could not be read."))
        }
    }

    struct Failure: LocalizedError {
        let message: String
        var errorDescription: String? { message }
    }

    static func message(for error: AgentError) -> String {
        switch error {
        case .notInstalled(let name): String(localized: "\(name) is not installed.")
        case .failed(let reason): reason.isEmpty ? String(localized: "The agent failed.") : reason
        case .invalidOutput: String(localized: "The agent's answer could not be read.")
        }
    }
}

extension RootScreen {
    /// *Open Claude Session*: an interactive Claude Code session in the terminal panel, in the pull request's
    /// worktree, opened with context (a delivery stage and its check, or a chat). Whatever is changed there, the user
    /// drives.
    func openClaudeSession(_ prompt: String, external: Bool = false) {
        guard let id = selection?.id else { return }
        Task {
            do {
                // Files of sessions that never started (Sylvra quit in between) go on the way.
                await ClaudeSessionCommand.removeLeftovers()
                // The prompt goes through a file Sylvra names: nothing from GitHub ends up in the command line.
                let file = FileManager.default.temporaryDirectory.appending(
                    path: "sylvra-session-\(UUID().uuidString).txt")
                try prompt.write(to: file, atomically: true, encoding: .utf8)
                let command = ClaudeSessionCommand.command(promptFile: file)
                let directory: URL
                do {
                    directory = try await TerminalWiring.checkout(for: id, environment: environment)
                } catch {
                    try? FileManager.default.removeItem(at: file)
                    throw error
                }
                guard external else {
                    environment.terminal.openTab(
                        title: String(localized: "Claude · #\(id.number)"), directory: directory, command: command,
                        isClaude: true)
                    return
                }
                // External terminals take no command, but they run a `.command` script.
                let script = file.deletingPathExtension().appendingPathExtension("command")
                try ClaudeSessionCommand.script(command: command, directory: directory).write(
                    to: script, atomically: true, encoding: .utf8)
                try FileManager.default.setAttributes([.posixPermissions: 0o755], ofItemAtPath: script.path)
                await environment.terminal.openInExternalTerminal(script)
            } catch {
                environment.terminal.errorMessage = String(
                    localized: "Could not open a Claude session: \(error.localizedDescription)")
            }
        }
    }
}
