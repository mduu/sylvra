import Foundation

/// Errors thrown when running external tools.
public enum ProcessRunnerError: Error, Equatable, Sendable {
    /// The executable could not be found in any known location.
    case executableNotFound(String)
    /// The process exited with a non-zero status.
    case failed(exitCode: Int32, standardError: String)
}

/// Runs child processes with `Foundation.Process`.
///
/// Arguments are passed as an array, never through a shell, so values coming from GitHub
/// (branch names, titles, paths) cannot inject commands.
public struct SystemProcessRunner: ProcessRunning {
    public init() {}

    public func run(_ executable: URL, arguments: [String], workingDirectory: URL?) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            process.environment = ExecutableLocator.environment

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr

            // Read the pipes concurrently so large outputs cannot block the child process.
            let outputBuffer = PipeBuffer(pipe: stdout)
            let errorBuffer = PipeBuffer(pipe: stderr)

            process.terminationHandler = { finished in
                let result = ProcessResult(
                    exitCode: finished.terminationStatus,
                    standardOutput: outputBuffer.finish(),
                    standardError: errorBuffer.finish()
                )
                continuation.resume(returning: result)
            }

            do {
                try process.run()
            } catch {
                continuation.resume(throwing: error)
            }
        }
    }
}

extension ProcessRunning {
    /// Runs a tool found via `ExecutableLocator` and returns its trimmed standard output.
    /// Throws `ProcessRunnerError.failed` for non-zero exit codes.
    public func output(of tool: String, arguments: [String], workingDirectory: URL? = nil) async throws -> String {
        guard let executable = ExecutableLocator.locate(tool) else {
            throw ProcessRunnerError.executableNotFound(tool)
        }
        let result = try await run(executable, arguments: arguments, workingDirectory: workingDirectory)
        guard result.exitCode == 0 else {
            throw ProcessRunnerError.failed(exitCode: result.exitCode, standardError: result.standardError)
        }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// Collects a pipe's output on a background queue.
private final class PipeBuffer: @unchecked Sendable {
    private let lock = NSLock()
    private var data = Data()
    private let pipe: Pipe

    init(pipe: Pipe) {
        self.pipe = pipe
        pipe.fileHandleForReading.readabilityHandler = { [weak self] handle in
            let chunk = handle.availableData
            guard !chunk.isEmpty, let self else { return }
            self.lock.lock()
            self.data.append(chunk)
            self.lock.unlock()
        }
    }

    func finish() -> String {
        pipe.fileHandleForReading.readabilityHandler = nil
        let rest = pipe.fileHandleForReading.readDataToEndOfFile()
        lock.lock()
        data.append(rest)
        let text = String(bytes: data, encoding: .utf8) ?? ""
        lock.unlock()
        return text
    }
}
