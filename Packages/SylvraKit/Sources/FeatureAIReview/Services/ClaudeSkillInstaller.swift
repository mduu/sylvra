import Foundation

/// The Claude Code skill that lets a local Claude Code session run Sylvra's AI review on its own changes through
/// the `sylvra` command line tool (`~/.claude/skills/sylvra-review/SKILL.md`). Written only when the user installs
/// it in the settings.
public struct ClaudeSkillInstaller: Sendable {
    public enum Status: Equatable, Sendable {
        case notInstalled
        case installed
        /// An older skill, or one for a Sylvra at another path (moved or another copy): reinstalling updates it.
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

    // swiftlint:disable function_body_length
    /// The skill: when to use the review, how to run it (in the background, it takes minutes), how to show its
    /// progress and how to treat its findings (suggestions to verify, not orders). One Markdown document;
    /// splitting it up would only make it harder to read.
    public static func skill(commandLineTool path: String) -> String {
        """
        ---
        name: \(skillName)
        description: Review the current branch's local changes (commits, uncommitted and new files) with \
        Sylvra's multi-model AI review — summary, merge verdict and risk, findings rated by impact and likelihood, \
        patterns. \
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
        takes a few minutes, longer with several models. Write the result to a file, so the command's output \
        holds only the progress:

        ```bash
        "\(path)" review -o "${TMPDIR:-/tmp}/sylvra-review.md"
        ```

        ## Show the progress

        The command prints one short line per step, for example:

        ```
        Reviewing 12 file(s) against origin/main with opus + fable (effort high)…
        [1/4 · 1:12] ✓ Core · Opus
        … 1 of 4 agents done, 3 running · 1:31
        Done in 2:41: 7 findings (2 major, 5 minor), merge risk medium, acceptable
        ```

        - If you have a tool that streams a background command's output line by line (such as Monitor), follow \
        the review with it and pass each `[n/m …] ✓` or `✗` line on to the user as one short sentence \
        ("Opus is done, 1 of 4 agents"). Skip the `▸` and `…` lines unless the user asks; never more than one \
        line per update.
        - Otherwise don't poll: wait for the completion notification. If the user asks how far the review is, \
        read the last lines of the command's output and answer with them.
        - When it is done, read the result file and continue below.

        **Hints**: when the user names something the review should pay particular attention to ("achte auf …", \
        "check especially …"), pass each point as `--hint "…"` — short, one point per hint. The review still \
        covers everything; the hints get extra attention and an answer each. Add a hint of your own only for \
        something you are unsure about in a change you made, and tell the user which hints you passed.

        ```bash
        "\(path)" review -o "${TMPDIR:-/tmp}/sylvra-review.md" --hint "thread safety of the cache" \
          --hint "the migration must stay backwards compatible"
        ```

        Options (only when the user asks for them; the defaults are the user's Sylvra settings):

        - `--base <branch>` — compare with another branch (default: `origin/HEAD`, `main` or `master`)
        - `--committed` — only committed changes, without work in progress
        - `--models opus,fable` · `--effort low|medium|high|xhigh|max` · `--agents <1–8>` · `--language <name>`
        - `--title "…"` / `--description "…"` — what the change is about, if the branch name and commits don't \
        say it
        - `--json` — Sylvra's structured result instead of Markdown; `-o <file>` writes it to a file

        Without `-o` the result (Markdown) goes to standard output; progress always goes to standard error. Exit \
        code 1 means the review failed (for example Claude Code isn't signed in); show the message. \
        `"\(path)" help` lists everything.

        ## Use the result

        1. Give the user the summary, the mergeability verdict and the merge risk (and the signs of unreviewed \
        code, if any), then what the reviewers say about each hint (section \
        *Reviewer hints*, if you passed any), then the findings, most severe first — short.
        2. The findings are suggestions from AI reviewers. Check each one against the code before you act on it, \
        and say which you agree with and which not, and why.
        3. Don't change code because of the review unless the user asks. When asked to fix, fix only the findings \
        you verified, then offer to review again.
        """
    }
    // swiftlint:enable function_body_length
}
