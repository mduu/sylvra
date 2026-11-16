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
}
