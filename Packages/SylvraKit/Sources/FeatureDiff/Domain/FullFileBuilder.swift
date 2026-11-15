import Foundation

/// Merges a file's diff into its full new content (full-file mode, see specs/ux.md §7.1).
public enum FullFileBuilder {
    /// One hunk spanning the whole file: unchanged lines as context, removed lines placed where they were.
    public static func hunk(newContent: String, diff: FileDiff) -> Hunk {
        let newLines = newContent.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
        let (changedByNewNumber, removedBefore) = index(diff)

        var lines: [DiffLine] = []
        var delta = 0  // old number = new number + delta
        let count = newLines.last == "" ? newLines.count - 1 : newLines.count
        for number in 1...max(count, 1) {
            for removed in removedBefore[number] ?? [] {
                lines.append(removed)
                delta += 1
            }
            guard number <= count else { break }
            if let line = changedByNewNumber[number] {
                lines.append(line)
                if line.kind == .added { delta -= 1 }
            } else {
                lines.append(
                    DiffLine(kind: .context, oldNumber: number + delta, newNumber: number, text: newLines[number - 1]))
            }
        }
        for (key, removed) in removedBefore where key > count {
            lines.append(contentsOf: removed)
        }
        return Hunk(
            oldStart: 1, oldCount: lines.count { $0.kind != .added }, newStart: 1, newCount: count, lines: lines)
    }

    /// Diff lines by new line number, and removed lines by the new line number they precede.
    private static func index(_ diff: FileDiff) -> (changed: [Int: DiffLine], removedBefore: [Int: [DiffLine]]) {
        var changed: [Int: DiffLine] = [:]
        var removedBefore: [Int: [DiffLine]] = [:]
        for hunk in diff.hunks {
            var nextNew = hunk.newStart
            for line in hunk.lines {
                if line.kind == .removed {
                    removedBefore[nextNew, default: []].append(line)
                } else if let number = line.newNumber {
                    changed[number] = line
                    nextNew = number + 1
                }
            }
        }
        return (changed, removedBefore)
    }
}
