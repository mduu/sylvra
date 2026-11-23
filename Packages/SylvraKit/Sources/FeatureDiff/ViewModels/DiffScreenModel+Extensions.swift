import Foundation
import SylvraCore

// MARK: - Since last review / new pushes

extension DiffScreenModel {
    /// Checks GitHub for a new head commit (called periodically by the diff screen).
    public func checkForNewCommits() async {
        guard let id = pullRequestID, let loaded = progress,
            let latest = try? await loader.loadReviewProgress(for: id), pullRequestID == id
        else { return }
        // Only a change is assigned: every assignment re-renders the diff.
        if latest.headSHA != loaded.headSHA, !hasNewCommits { hasNewCommits = true }
    }

    func loadProgress(_ id: PullRequestID) async {
        guard let loaded = try? await loader.loadReviewProgress(for: id), pullRequestID == id else { return }
        if progress != loaded { progress = loaded }
        if hasNewCommits { hasNewCommits = false }
    }

    func loadSinceReview() async {
        guard let id = pullRequestID, let progress, let base = progress.lastReviewedSHA else {
            sinceReviewFiles = []
            return
        }
        isLoadingSinceReview = true
        defer { isLoadingSinceReview = false }
        do {
            let loaded = try await loader.loadDiff(for: id, from: base, to: progress.headSHA)
            guard pullRequestID == id else { return }
            if progress.isRewrittenSinceReview, let files = diff?.files {
                let restricted = SinceReviewFilter.restrict(loaded, to: files)
                sinceReviewFiles = restricted.files
                sinceReviewHiddenFiles = restricted.hidden
            } else {
                sinceReviewFiles = loaded
                sinceReviewHiddenFiles = 0
            }
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
            guard let pullRequestID, let ref = progress?.headSHA ?? headSHA,
                expandingPaths.insert(file.path).inserted
            else { return }
            defer { expandingPaths.remove(file.path) }
            let loader = loader
            let path = file.path
            do {
                // The first expansion loads the whole file: split off the main actor, the hunk header shows
                // a spinner meanwhile.
                let lines = try await Task.detached {
                    try await loader.loadFileContent(for: pullRequestID, path: path, ref: ref)
                        .split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
                }.value
                guard self.pullRequestID == pullRequestID else { return }
                headLines[file.path] = lines
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

// MARK: - Head changes

extension DiffScreenModel {
    /// The pull request's head became known or moved. Learning it (the details load next to the diff) needs no
    /// new diff: restarting the load for it fetched the diff twice per selection. A new head after a push does.
    public func headChanged(to newHead: String?, for id: PullRequestID?) async {
        guard let id, id == pullRequestID, let newHead, newHead != headSHA else { return }
        if headSHA == nil {
            headSHA = newHead
            if scope == .fullFile { await loadFullFile() }
        } else {
            await load(id, headSHA: newHead)
        }
    }
}
