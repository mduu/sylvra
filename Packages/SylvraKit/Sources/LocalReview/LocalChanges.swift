import Foundation
import Platform

/// The changes of a local branch: what it adds to its base branch, plus uncommitted and untracked files.
/// Only reads the repository (never stages, stashes or writes anything).
public struct LocalChanges: Sendable {
    public let root: URL
    /// The base as given or found (`origin/main`).
    public let base: String
    public let branch: String?
    /// Unified diff with `a/` and `b/` prefixes.
    public let diff: String
    /// Subjects and bodies of the branch's commits, oldest first.
    public let commitMessages: [String]
    public let includesUncommitted: Bool

    public enum LoadError: Error, LocalizedError, Equatable {
        case notARepository(String)
        case noBase
        case baseNotFound(String)

        public var errorDescription: String? {
            switch self {
            case .notARepository(let path): "\(path) is not inside a git repository."
            case .noBase: "Couldn't find the base branch (origin/HEAD, main or master). Pass --base <branch>."
            case .baseNotFound(let base): "Couldn't find '\(base)' in this repository."
            }
        }
    }

    /// Untracked files larger than this are left out (generated or binary files).
    static let untrackedSizeLimit = 512 * 1024

    public static func load(
        in directory: URL, base requestedBase: String?, committedOnly: Bool,
        runner: any ProcessRunning = SystemProcessRunner()
    ) async throws -> LocalChanges {
        let git = Git(runner: runner)
        guard let rootPath = try? await git.output(["rev-parse", "--show-toplevel"], in: directory) else {
            throw LoadError.notARepository(directory.path)
        }
        let root = URL(fileURLWithPath: rootPath, isDirectory: true)
        let base = try await resolveBase(requestedBase, git: git, root: root)
        let mergeBase = try await git.output(["merge-base", base, "HEAD"], in: root)
        let branch = try? await git.output(["rev-parse", "--abbrev-ref", "HEAD"], in: root)
        // Fixed prefixes and no external diff tools or colors, whatever the user's git config says.
        let diffOptions = ["--no-color", "--no-ext-diff", "--find-renames", "--src-prefix=a/", "--dst-prefix=b/"]
        var diff = try await git.output(
            ["diff"] + diffOptions + (committedOnly ? [mergeBase, "HEAD"] : [mergeBase]), in: root, trimmed: false)
        if !committedOnly {
            for file in try await untrackedFiles(git: git, root: root) {
                // `--no-index` exits with 1 when the files differ, which they always do here.
                diff += try await git.output(
                    ["diff", "--no-index"] + diffOptions + ["--", "/dev/null", file], in: root, trimmed: false,
                    allowedExitCodes: [0, 1])
            }
        }
        let log = try await git.output(
            ["log", "--reverse", "--format=%s%n%n%b%x1e", "\(mergeBase)..HEAD"], in: root, trimmed: false)
        let messages = log.split(separator: "\u{1e}").map { $0.trimmingCharacters(in: .whitespacesAndNewlines) }
            .filter { !$0.isEmpty }
        return LocalChanges(
            root: root, base: base, branch: branch == "HEAD" ? nil : branch, diff: diff, commitMessages: messages,
            includesUncommitted: !committedOnly)
    }

    /// The given base, or the remote's default branch, `main` or `master`.
    static func resolveBase(_ requested: String?, git: Git, root: URL) async throws -> String {
        if let requested {
            guard (try? await git.output(["rev-parse", "--verify", "--quiet", requested], in: root)) != nil else {
                throw LoadError.baseNotFound(requested)
            }
            return requested
        }
        if let remoteHead = try? await git.output(
            ["symbolic-ref", "--quiet", "--short", "refs/remotes/origin/HEAD"], in: root),
            !remoteHead.isEmpty
        {
            return remoteHead
        }
        for candidate in ["origin/main", "main", "origin/master", "master"] {
            // A `where` clause can't await.
            guard (try? await git.output(["rev-parse", "--verify", "--quiet", candidate], in: root)) != nil else {
                continue
            }
            return candidate
        }
        throw LoadError.noBase
    }

    /// New files git doesn't track yet (ignored ones excluded), small enough to be source code.
    static func untrackedFiles(git: Git, root: URL) async throws -> [String] {
        let list = try await git.output(["ls-files", "--others", "--exclude-standard", "-z"], in: root, trimmed: false)
        return list.split(separator: "\0").map(String.init).filter { path in
            let size = (try? FileManager.default.attributesOfItem(atPath: root.appending(path: path).path))?[.size]
            return ((size as? Int) ?? 0) <= untrackedSizeLimit
        }
    }
}

/// `git` with arguments as an array (never a shell string), exit codes checked.
struct Git: Sendable {
    let runner: any ProcessRunning

    func output(
        _ arguments: [String], in directory: URL, trimmed: Bool = true, allowedExitCodes: Set<Int32> = [0]
    ) async throws -> String {
        guard let git = ExecutableLocator.locate("git") else { throw GitError.notInstalled }
        let result = try await runner.run(git, arguments: arguments, workingDirectory: directory)
        guard allowedExitCodes.contains(result.exitCode) else {
            throw GitError.failed(
                command: "git " + arguments.joined(separator: " "),
                message: result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return trimmed ? result.standardOutput.trimmingCharacters(in: .whitespacesAndNewlines) : result.standardOutput
    }
}
