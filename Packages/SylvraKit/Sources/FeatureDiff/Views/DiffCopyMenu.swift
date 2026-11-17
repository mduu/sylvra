import SwiftUI

/// Right-click menu of a diff line (pure): copy the line, its hunk in either version, or the hunk as a diff.
struct DiffCopyMenu: View {
    /// The new-side and old-side line of the row (side by side can have both).
    let newLine: DiffLine?
    let oldLine: DiffLine?
    let hunk: Hunk
    let copy: (String) -> Void

    var body: some View {
        if let newLine, let oldLine, newLine != oldLine {
            Button("Copy New Line") { copy(newLine.text) }
            Button("Copy Old Line") { copy(oldLine.text) }
        } else if let line = newLine ?? oldLine {
            Button("Copy Line") { copy(line.text) }
        }
        Divider()
        Button("Copy Hunk") { copy(DiffCopy.code(hunk.lines, version: .new)) }
        Button("Copy Hunk (Old Version)") { copy(DiffCopy.code(hunk.lines, version: .old)) }
        Button("Copy Hunk as Diff") { copy(DiffCopy.unified(hunk)) }
    }
}
