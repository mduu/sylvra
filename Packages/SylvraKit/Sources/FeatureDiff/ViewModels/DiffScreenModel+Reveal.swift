import Foundation
import SylvraCore

extension DiffScreenModel {
    /// Shows a file in the diff, e.g. from the AI reading order or pattern evidence: leaves a single commit
    /// that doesn't contain it, expands it if it's collapsed (viewed, noise) and scrolls to `line` or to its
    /// first change — also when it's already the selected file.
    public func reveal(_ path: String, line requestedLine: Int? = nil) async {
        if selectedCommit != nil, !files.contains(where: { $0.path == path }) {
            await showCommit(nil)
        }
        guard let file = files.first(where: { $0.path == path }) else {
            selectedPath = path
            return
        }
        let firstChange = file.hunks.lazy.flatMap(\.lines).first { $0.kind != .context }
        let line = firstChange?.newNumber ?? firstChange?.oldNumber ?? file.hunks.first?.newStart ?? 1
        focus(path: path, line: requestedLine ?? line)
    }

    /// Shows an AI finding: findings refer to all changes, so a single commit (other line numbers) is left.
    public func revealFinding(path: String, line: Int) async {
        if selectedCommit != nil { await showCommit(nil) }
        focus(path: path, line: line)
    }

    /// The shown new-side line closest to `line` (itself if shown); nil when no hunk has a new-side line.
    nonisolated static func nearestShownLine(to line: Int, in hunks: [Hunk]) -> Int? {
        let shown = hunks.lazy.flatMap(\.lines).compactMap(\.newNumber)
        return shown.min { abs($0 - line) < abs($1 - line) || (abs($0 - line) == abs($1 - line) && $0 < $1) }
    }
}

extension DiffScreenModel {
    /// A click on a file's header in the diff: the navigator highlights the file, opens its folders and scrolls
    /// it into view; the diff stays where it is (the header is already on screen).
    public func selectInNavigator(_ path: String) {
        if selectedPath != path {
            keepsDiffPosition = true
            selectedPath = path
        }
        collapsedFolders = collapsedFolders.filter { !path.hasPrefix($0 + "/") }
        navigatorRevealToken += 1
    }
}
