import Foundation

/// The shell commands that start an interactive Claude Code session with an opening prompt from a file (pure).
///
/// The prompt goes through a file Sylvra names, so nothing from GitHub ends up in a command line. The file holds
/// pull request and delivery context and is deleted as soon as it is read — and the `.command` script for the
/// external terminal deletes itself.
public enum ClaudeSessionCommand {
    /// Reads the prompt, deletes its file, starts `claude` with it.
    public static func command(promptFile: URL) -> String {
        let path = quoted(promptFile.path)
        return "prompt=\"$(cat \(path))\"; rm -f \(path); claude \"$prompt\""
    }

    /// A `.command` script for the external terminal: deletes itself, then runs `command` in `directory`.
    public static func script(command: String, directory: URL) -> String {
        "#!/bin/zsh -l\nrm -f \"$0\"\ncd \(quoted(directory.path)) && \(command)\n"
    }

    /// Deletes prompt files and scripts older than a day that a session never read (Sylvra quit before the
    /// terminal started, say). Runs off the main actor.
    public static func removeLeftovers(
        in directory: URL = FileManager.default.temporaryDirectory, now: Date = .now
    ) async {
        await Task.detached(priority: .utility) {
            let manager = FileManager.default
            let files =
                (try? manager.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.contentModificationDateKey])) ?? []
            for file in files where file.lastPathComponent.hasPrefix("sylvra-session-") {
                let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?
                    .contentModificationDate
                if let modified, now.timeIntervalSince(modified) > 86_400 { try? manager.removeItem(at: file) }
            }
        }.value
    }

    /// `'…'` for the shell; a `'` inside becomes `'\''`.
    static func quoted(_ text: String) -> String {
        "'" + text.replacingOccurrences(of: "'", with: "'\\''") + "'"
    }
}
