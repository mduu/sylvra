import Foundation

/// Errors from git operations.
public enum GitError: Error, Equatable, Sendable {
    case notInstalled
    case failed(command: String, message: String)
}

/// Runs the system `git` binary (see specs/architecture.md §6).
public struct GitRunner: Sendable {
    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning = SystemProcessRunner()) {
        self.runner = runner
    }

    /// Runs `git <arguments>` in `directory` and returns the trimmed standard output.
    @discardableResult
    public func run(_ arguments: [String], in directory: URL? = nil) async throws -> String {
        guard let git = ExecutableLocator.locate("git") else { throw GitError.notInstalled }
        let result = try await runner.run(git, arguments: arguments, workingDirectory: directory)
        guard result.exitCode == 0 else {
            let message = result.standardError.trimmingCharacters(in: .whitespacesAndNewlines)
            throw GitError.failed(command: "git " + arguments.joined(separator: " "), message: message)
        }
        return result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines)
    }

    /// `true` if the working tree has no uncommitted changes (untracked files count as changes).
    public func isClean(_ directory: URL) async throws -> Bool {
        try await run(["status", "--porcelain"], in: directory).isEmpty
    }

    /// The current branch name, or `nil` when detached.
    public func currentBranch(_ directory: URL) async throws -> String? {
        let name = try await run(["rev-parse", "--abbrev-ref", "HEAD"], in: directory)
        return name == "HEAD" ? nil : name
    }
}

/// Parses GitHub remote URLs (`git@github.com:owner/repo.git`, `https://github.com/owner/repo`).
public enum GitHubRemote {
    public static func ownerAndName(from url: String) -> (owner: String, name: String)? {
        let trimmed = url.trimmingCharacters(in: .whitespacesAndNewlines)
        guard let hostRange = trimmed.range(of: "github.com") else { return nil }
        var path = trimmed[hostRange.upperBound...].drop { $0 == ":" || $0 == "/" }
        if path.hasSuffix(".git") { path = path.dropLast(4) }
        let parts = path.split(separator: "/")
        guard parts.count >= 2 else { return nil }
        return (String(parts[0]), String(parts[1]))
    }
}
