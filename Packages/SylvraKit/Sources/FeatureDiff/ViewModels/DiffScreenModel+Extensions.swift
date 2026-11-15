import Foundation
import SylvraCore

// MARK: - Since last review / new pushes

extension DiffScreenModel {
    /// Checks GitHub for a new head commit (called periodically by the diff screen).
    public func checkForNewCommits() async {
        guard let id = pullRequestID, let loaded = progress,
            let latest = try? await loader.loadReviewProgress(for: id), pullRequestID == id
        else { return }
        if latest.headSHA != loaded.headSHA { hasNewCommits = true }
    }

    func loadProgress(_ id: PullRequestID) async {
        guard let loaded = try? await loader.loadReviewProgress(for: id), pullRequestID == id else { return }
        progress = loaded
        hasNewCommits = false
    }

    func loadSinceReview() async {
        guard let id = pullRequestID, let progress, let base = progress.lastReviewedSHA else {
            sinceReviewFiles = []
            return
        }
        do {
            let loaded = try await loader.loadDiff(for: id, from: base, to: progress.headSHA)
            guard pullRequestID == id else { return }
            sinceReviewFiles = loaded
        } catch {
            sinceReviewFiles = []
            let reason = error.localizedDescription
            lastError = String(
                localized: "Couldn't load the changes since your last review (gone after a force push?): \(reason)")
        }
    }
}

// MARK: - Context expansion

extension DiffScreenModel {
    /// Lines still hidden above each hunk of a file.
    public func hiddenAbove(_ file: FileDiff) -> [Int] {
        let revealed = revealedContext[file.path] ?? [:]
        return ContextExpander.hiddenAbove(file.hunks).enumerated().map { index, hidden in
            max(hidden - (revealed[index] ?? 0), 0)
        }
    }

    /// Reveals `count` more lines above a hunk (`nil`: the whole gap).
    public func expandContext(_ file: FileDiff, hunk index: Int, by count: Int?) async {
        if headLines[file.path] == nil {
            guard let pullRequestID, let ref = progress?.headSHA ?? headSHA else { return }
            do {
                let content = try await loader.loadFileContent(for: pullRequestID, path: file.path, ref: ref)
                guard self.pullRequestID == pullRequestID else { return }
                headLines[file.path] = content.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
            } catch {
                lastError = String(localized: "Couldn't load \(file.fileName): \(error.localizedDescription)")
                return
            }
        }
        let gap = ContextExpander.hiddenAbove(file.hunks)[index]
        let current = revealedContext[file.path]?[index] ?? 0
        revealedContext[file.path, default: [:]][index] = min(count.map { current + $0 } ?? gap, gap)
    }
}

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
