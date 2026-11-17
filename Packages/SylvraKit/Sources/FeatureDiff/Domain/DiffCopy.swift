import AppKit
import Foundation

/// Text of diff lines for the clipboard: one version of the code, or the change as a unified diff.
enum DiffCopy {
    enum Version { case new, old }

    /// The code of `version` (context lines plus the lines added or removed on that side).
    static func code(_ lines: [DiffLine], version: Version) -> String {
        lines.filter { version == .new ? $0.kind != .removed : $0.kind != .added }
            .map(\.text)
            .joined(separator: "\n")
    }

    /// The lines with `+`, `-` and space prefixes, ready to paste into a chat or an issue.
    static func unified(_ hunk: Hunk) -> String {
        let header = "@@ -\(hunk.oldStart),\(hunk.oldCount) +\(hunk.newStart),\(hunk.newCount) @@"
        let lines = hunk.lines.map { line in
            switch line.kind {
            case .added: "+" + line.text
            case .removed: "-" + line.text
            case .context: " " + line.text
            }
        }
        return ([header] + lines).joined(separator: "\n")
    }

    @MainActor static func toClipboard(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }
}
