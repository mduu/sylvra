import Foundation

/// One tab of the terminal panel: a shell (or a command followed by a shell) in a working directory.
public struct TerminalSession: Identifiable, Hashable, Sendable {
    public let id: UUID
    public var title: String
    public let directory: URL
    /// Shell command run first (custom tools); `nil` starts an interactive shell.
    public let command: String?
    /// Exit code once the shell process has exited.
    public var exitCode: Int32?
    public var hasExited: Bool
    /// A Claude Code session (opened by Sylvra or titled so by Claude Code): remembered across restarts.
    public var isClaude: Bool
    /// Left over from before Sylvra was restarted: no process, it can be continued (`claude --continue`).
    public var isRestored = false
    /// The program rang the bell while the tab was not in view (Claude Code waiting for input, say).
    public var needsAttention = false

    public init(
        id: UUID = UUID(), title: String, directory: URL, command: String? = nil, isClaude: Bool = false
    ) {
        self.id = id
        self.title = title
        self.directory = directory
        self.command = command
        self.isClaude = isClaude
        exitCode = nil
        hasExited = false
    }
}

/// What is remembered of a Claude session for the next launch: where it ran and what it was called.
struct SavedClaudeSession: Codable, Equatable {
    let title: String
    let directory: URL
}
