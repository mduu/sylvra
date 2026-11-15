import Foundation

// MARK: - Change navigation (n / p)

extension DiffScreenModel {

    /// Starts of changed blocks in review order, in expanded files.
    public var changeTargets: [ChangeTarget] {
        orderedFiles.filter { !isCollapsed($0) }.flatMap { file in
            Self.changeLines(in: hunks(for: file)).map { ChangeTarget(path: file.path, line: $0) }
        }
    }

    /// New-side line numbers where blocks of changes start (a removal anchors at the next new line).
    nonisolated static func changeLines(in hunks: [Hunk]) -> [Int] {
        var result: [Int] = []
        for hunk in hunks {
            var inChange = false
            var pending = false
            for line in hunk.lines {
                let changed = line.kind != .context
                if changed && !inChange { pending = true }
                inChange = changed
                if pending, let number = line.newNumber {
                    result.append(number)
                    pending = false
                }
            }
        }
        return result
    }

    /// Jumps to the next / previous block of changes.
    public func selectChange(offset: Int) {
        let targets = changeTargets
        guard !targets.isEmpty else { return }
        let current =
            lastChange.flatMap { targets.firstIndex(of: $0) }
            ?? selectedPath.flatMap { path in targets.firstIndex { $0.path == path } }.map { $0 - (offset > 0 ? 1 : 0) }
            ?? (offset > 0 ? -1 : targets.count)
        let target = targets[min(max(current + offset, 0), targets.count - 1)]
        lastChange = target
        focus(path: target.path, line: target.line)
    }
}

// MARK: - Find in diff (⌘F)

extension DiffScreenModel {

    /// Lines containing the query (case-insensitive) in review order; matches on removed lines anchor at the next
    /// new-side line. Collapsed files are searched too and expand when a match is shown.
    public var searchMatches: [ChangeTarget] {
        let query = searchQuery.trimmingCharacters(in: .whitespaces)
        guard query.count >= 2 else { return [] }
        var result: [ChangeTarget] = []
        for file in orderedFiles {
            for hunk in hunks(for: file) {
                var pending = false
                for line in hunk.lines {
                    if line.text.range(of: query, options: .caseInsensitive) != nil { pending = true }
                    guard pending, let number = line.newNumber else { continue }
                    let target = ChangeTarget(path: file.path, line: number)
                    if result.last != target { result.append(target) }
                    pending = false
                }
            }
        }
        return result
    }

    /// Shows the next / previous match.
    public func selectSearchMatch(offset: Int) {
        let matches = searchMatches
        guard !matches.isEmpty else { return }
        let current = currentSearchMatch.flatMap { matches.firstIndex(of: $0) } ?? (offset > 0 ? -1 : matches.count)
        // Wraps around like Find in other apps.
        let target = matches[(current + offset + matches.count) % matches.count]
        currentSearchMatch = target
        focus(path: target.path, line: target.line)
    }
}
