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

    public func run(
        _ executable: URL, arguments: [String], workingDirectory: URL?, input: Data?
    ) async throws -> ProcessResult {
        let box = ProcessBox()
        return try await withTaskCancellationHandler {
            try await launch(
                executable, arguments: arguments, workingDirectory: workingDirectory, input: input, box: box)
        } onCancel: {
            box.terminate()
        }
    }

    private func launch(
        _ executable: URL, arguments: [String], workingDirectory: URL?, input: Data?, box: ProcessBox
    ) async throws -> ProcessResult {
        try await withCheckedThrowingContinuation { continuation in
            let process = Process()
            box.set(process)
            process.executableURL = executable
            process.arguments = arguments
            process.currentDirectoryURL = workingDirectory
            process.environment = ExecutableLocator.environment

            let stdout = Pipe()
            let stderr = Pipe()
            process.standardOutput = stdout
            process.standardError = stderr
            let stdin = input.map { _ in Pipe() }
            if let stdin { process.standardInput = stdin } else { process.standardInput = FileHandle.nullDevice }

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
                if let stdin, let input {
                    DispatchQueue.global(qos: .userInitiated).async {
                        // `write(contentsOf:)` throws instead of raising when the child already exited
                        // (SIGPIPE itself is ignored at app start, see `ProcessSignals`).
                        try? stdin.fileHandleForWriting.write(contentsOf: input)
                        try? stdin.fileHandleForWriting.close()
                    }
                }
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
        let text = String(decoding: data, as: UTF8.self)  // lossy: never drop non-UTF-8 output
        lock.unlock()
        return text
    }
}

/// Holds the running process so a task cancellation can terminate it.
private final class ProcessBox: @unchecked Sendable {
    private let lock = NSLock()
    private var process: Process?
    private var isCancelled = false

    func set(_ process: Process) {
        lock.lock()
        self.process = process
        let cancelled = isCancelled
        lock.unlock()
        if cancelled { process.terminate() }
    }

    func terminate() {
        lock.lock()
        isCancelled = true
        let process = process
        lock.unlock()
        if process?.isRunning == true { process?.terminate() }
    }
}

/// Process-wide signal setup: writing to a pipe whose reader exited must not kill the app.
public enum ProcessSignals {
    public static func ignoreBrokenPipes() {
        signal(SIGPIPE, SIG_IGN)
    }
}
