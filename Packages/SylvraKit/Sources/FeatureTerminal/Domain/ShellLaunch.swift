import Darwin
import Foundation
import Platform

/// How a terminal session's process is launched (pure, unit-tested).
public struct ShellLaunch: Equatable, Sendable {
    public let executable: String
    public let arguments: [String]
    /// `argv[0]`; a leading `-` makes the shell a login shell.
    public let execName: String
    public let environment: [String]

    /// Shells that understand the POSIX wrapper used for commands.
    static let posixShells: Set<String> = ["sh", "bash", "zsh", "ksh", "dash"]

    /// Prints the command dimmed, runs it, shows its exit status and continues with an interactive login shell.
    /// The command is passed as `$1` and the shell as `$0`, so nothing is spliced into the script.
    static let commandWrapper = """
        printf '\\033[2m$ %s\\033[0m\\n' "$1"; eval "$1"; code=$?; \
        printf '\\n\\033[2m[exited with status %d]\\033[0m\\n' "$code"; exec "$0" -l
        """

    /// Launch description for `shell`, optionally running `command` first.
    public static func make(shell: String, command: String?, baseEnvironment: [String: String]) -> ShellLaunch {
        let name = (shell as NSString).lastPathComponent
        let environment = Self.environment(base: baseEnvironment, shell: shell)
        guard let command else {
            return ShellLaunch(executable: shell, arguments: [], execName: "-" + name, environment: environment)
        }
        // Non-POSIX shells (fish, nu, …) run the wrapper via zsh and continue in the user's shell afterwards.
        let runner = posixShells.contains(name) ? shell : "/bin/zsh"
        return ShellLaunch(
            executable: runner, arguments: ["-l", "-c", commandWrapper, shell, command],
            execName: (runner as NSString).lastPathComponent, environment: environment)
    }

    /// The app's environment plus terminal capabilities, as sorted `KEY=value` pairs. Without the variables of a
    /// Claude Code or tmux session Sylvra may have been started from: a `claude` in the panel would think it runs
    /// nested, tmux tools would talk to the wrong server.
    static func environment(base: [String: String], shell: String) -> [String] {
        var values = base.filter { !isInheritedSessionVariable($0.key) }
        values["TERM"] = "xterm-256color"
        values["COLORTERM"] = "truecolor"
        values["TERM_PROGRAM"] = "Sylvra"
        values["SHELL"] = shell
        if values["LANG"] == nil { values["LANG"] = "en_US.UTF-8" }
        return values.sorted { $0.key < $1.key }.map { "\($0.key)=\($0.value)" }
    }

    static func isInheritedSessionVariable(_ name: String) -> Bool {
        ExecutableLocator.isCallerSessionVariable(name) || name == "TMUX" || name == "TMUX_PANE"
    }

    /// Lines kept above the screen; SwiftTerm's default of 500 loses long test or Claude Code output.
    public static let scrollback = 10_000

    /// The user's login shell from the user database (falls back to `$SHELL`, then zsh).
    public static func loginShell(environment: [String: String] = ProcessInfo.processInfo.environment) -> String {
        if let entry = getpwuid(getuid()), let shell = entry.pointee.pw_shell {
            let path = String(cString: shell)
            if !path.isEmpty { return path }
        }
        return environment["SHELL"] ?? "/bin/zsh"
    }
}
