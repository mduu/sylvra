import Foundation

/// Turns a finished child process into a Commands panel entry without secrets or code.
enum ProcessLogEntry {
    /// git subcommands whose output is code (diffs, file contents).
    static let codeSubcommands: Set<String> = ["diff", "show", "cat-file", "blame", "log", "grep"]

    /// What was run.
    struct Invocation {
        let executable: URL
        let arguments: [String]
        let workingDirectory: URL?
        let input: Data?
        let started: Date
    }

    static func make(
        _ invocation: Invocation, result: Result<ProcessResult, any Error>, isCancelled: Bool
    ) -> CommandLogEntry {
        let (executable, arguments, started) = (invocation.executable, invocation.arguments, invocation.started)
        let (workingDirectory, input) = (invocation.workingDirectory, invocation.input)
        let name = executable.lastPathComponent
        let kind: CommandLogEntry.Kind = name == "git" ? .git : .process
        var request = workingDirectory.map { "in \($0.path)" } ?? ""
        if let input {
            request += (request.isEmpty ? "" : "\n") + "stdin: \(input.count.formatted(.byteCount(style: .file)))"
        }
        let duration = Date.now.timeIntervalSince(started)
        let title = CommandLogText.commandLine(name, arguments)
        switch result {
        case .success(let output):
            let failed = output.exitCode != 0
            return CommandLogEntry(
                kind: kind, title: title, startedAt: started, duration: duration,
                status: isCancelled ? "cancelled" : "exit \(output.exitCode)", isFailure: failed && !isCancelled,
                request: request.isEmpty ? nil : request,
                response: response(name: name, arguments: arguments, output: output))
        case .failure(let error):
            return CommandLogEntry(
                kind: kind, title: title, startedAt: started, duration: duration,
                status: isCancelled ? "cancelled" : "failed", isFailure: !isCancelled,
                request: request.isEmpty ? nil : request, response: String(describing: error))
        }
    }

    /// Standard output only where it's neither a secret (`gh auth token`) nor code; errors always.
    static func response(name: String, arguments: [String], output: ProcessResult) -> String {
        let stdout: String
        let bytes = output.standardOutput.utf8.count
        if arguments.contains("token") || arguments.contains("--show-token") {
            stdout = CommandLogText.sizeOnly(bytes, reason: "secret, not shown")
        } else if name == "git", let subcommand = arguments.first(where: { !$0.hasPrefix("-") }),
            codeSubcommands.contains(subcommand)
        {
            stdout = CommandLogText.sizeOnly(bytes, reason: "code, not shown")
        } else if name != "git" {
            // Agent CLIs answer with reviews that quote code.
            stdout = CommandLogText.sizeOnly(bytes, reason: "output not shown")
        } else {
            stdout = CommandLogText.preview(output.standardOutput)
        }
        let stderr = output.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
        return stderr.isEmpty ? stdout : stdout + "\n\nstderr:\n" + CommandLogText.preview(stderr)
    }
}
