import Foundation
import SylvraCore

/// Commit-by-commit review: show one commit's changes, step through the commits.
extension DiffScreenModel {
    /// Position of the shown commit (1-based) among the PR's commits.
    public var commitPosition: (number: Int, count: Int)? {
        guard let selectedCommit, let index = commits.firstIndex(of: selectedCommit) else { return nil }
        return (index + 1, commits.count)
    }

    /// Shows one commit's changes; `nil` goes back to all changes of the PR.
    public func showCommit(_ commit: Commit?) async {
        guard let commit else {
            selectedCommit = nil
            commitFiles = nil
            return
        }
        guard let pullRequestID else { return }
        let id = pullRequestID
        selectedCommit = commit
        commitFiles = nil
        selectedPath = nil
        isLoadingCommit = true
        defer { isLoadingCommit = false }
        do {
            let files = try await loader.loadCommitDiff(for: id, sha: commit.sha)
            // The reviewer may have moved on to another commit or PR meanwhile.
            guard pullRequestID == id, selectedCommit == commit else { return }
            commitFiles = files
        } catch {
            guard pullRequestID == id, selectedCommit == commit else { return }
            commitFiles = []
            lastError = String(
                localized: "Couldn't load commit \(commit.shortSHA): \(error.localizedDescription)")
        }
    }

    /// Next / previous commit (`⌥]` / `⌥[`); from all changes, starts at the first or last commit.
    public func selectCommit(offset: Int) async {
        guard !commits.isEmpty else { return }
        let current = selectedCommit.flatMap(commits.firstIndex(of:)) ?? (offset > 0 ? -1 : commits.count)
        let target = current + offset
        guard commits.indices.contains(target) else { return }
        await showCommit(commits[target])
    }
}
