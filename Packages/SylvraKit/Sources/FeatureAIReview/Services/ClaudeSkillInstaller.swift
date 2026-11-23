import Foundation

/// The Claude Code skill that lets a local Claude Code session run Sylvra's AI review on its own changes through
/// the `sylvra` command line tool (`~/.claude/skills/sylvra-review/SKILL.md`). Written only when the user installs
/// it in the settings.
public struct ClaudeSkillInstaller: Sendable {
    public enum Status: Equatable, Sendable {
        case notInstalled
        case installed
        /// Installed for a Sylvra at another path (moved or another copy): reinstalling points it here.
        case outdated
    }

    public static let skillName = "sylvra-review"

    /// The `sylvra` tool inside the app bundle.
    public let commandLineTool: URL
    private let skillsDirectory: URL

    public init(
        commandLineTool: URL,
        skillsDirectory: URL = FileManager.default.homeDirectoryForCurrentUser.appending(path: ".claude/skills")
    ) {
        self.commandLineTool = commandLineTool
        self.skillsDirectory = skillsDirectory
    }

    public var skillFile: URL { skillsDirectory.appending(path: "\(Self.skillName)/SKILL.md") }

    public var status: Status {
        guard let installed = try? String(contentsOf: skillFile, encoding: .utf8) else { return .notInstalled }
        return installed == Self.skill(commandLineTool: commandLineTool.path) ? .installed : .outdated
    }

    public func install() throws {
        try FileManager.default.createDirectory(
            at: skillFile.deletingLastPathComponent(), withIntermediateDirectories: true)
        try Data(Self.skill(commandLineTool: commandLineTool.path).utf8).write(to: skillFile, options: .atomic)
    }

    public func uninstall() throws {
        try FileManager.default.removeItem(at: skillFile.deletingLastPathComponent())
    }

    /// The skill: when to use the review, how to run it (in the background, it takes minutes) and how to treat
    /// its findings (suggestions to verify, not orders).
    public static func skill(commandLineTool path: String) -> String {
        """
        ---
        name: \(skillName)
        description: Review the current branch's local changes (commits, uncommitted and new files) with \
        Sylvra's multi-model AI review — summary, merge risk, findings rated by impact and likelihood, patterns. \
        Use when the user asks for a Sylvra review, a multi-model review or a second opinion on their changes \
        before pushing or opening a pull request.
        ---

        # Sylvra review

        Sylvra runs several AI reviewers (one per model, large changes split across parallel agents), merges and \
        de-duplicates their findings, and rates each by severity, impact and likelihood. It reviews what the \
        current branch adds to its base branch, including uncommitted and new files. Its agents only read the \
        repository; nothing is changed, committed or posted.

        ## Run it

        Run from the repository with the Bash tool **in the background** (`run_in_background: true`) — a review \
        takes a few minutes, longer with several models. Wait for the completion notification; don't poll.

        ```bash
        "\(path)" review
        ```

        Options (only when the user asks for them; the defaults are the user's Sylvra settings):

        - `--base <branch>` — compare with another branch (default: `origin/HEAD`, `main` or `master`)
        - `--committed` — only committed changes, without work in progress
        - `--models opus,fable` · `--effort low|medium|high|xhigh|max` · `--agents <1–8>` · `--language <name>`
        - `--title "…"` / `--description "…"` — what the change is about, if the branch name and commits don't \
        say it
        - `--json` — Sylvra's structured result instead of Markdown; `-o <file>` writes it to a file

        The result (Markdown) is on standard output, progress on standard error. Exit code 1 means the review \
        failed (for example Claude Code isn't signed in); show the message. `"\(path)" help` lists everything.

        ## Use the result

        1. Give the user the summary and the merge risk, then the findings, most severe first — short.
        2. The findings are suggestions from AI reviewers. Check each one against the code before you act on it, \
        and say which you agree with and which not, and why.
        3. Don't change code because of the review unless the user asks. When asked to fix, fix only the findings \
        you verified, then offer to review again.
        """
    }
}
