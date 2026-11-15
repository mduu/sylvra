import Foundation

/// Result of a finished child process.
public struct ProcessResult: Sendable {
    public let exitCode: Int32
    public let standardOutput: String
    public let standardError: String

    public init(exitCode: Int32, standardOutput: String, standardError: String) {
        self.exitCode = exitCode
        self.standardOutput = standardOutput
        self.standardError = standardError
    }
}

/// Runs external tools (`git`, agent CLIs, IDE launchers).
///
/// Arguments are always passed as an array — never as an interpolated shell string.
public protocol ProcessRunning: Sendable {
    func run(_ executable: URL, arguments: [String], workingDirectory: URL?) async throws -> ProcessResult
}
