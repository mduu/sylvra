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

    public init(id: UUID = UUID(), title: String, directory: URL, command: String? = nil) {
        self.id = id
        self.title = title
        self.directory = directory
        self.command = command
        exitCode = nil
        hasExited = false
    }
}
