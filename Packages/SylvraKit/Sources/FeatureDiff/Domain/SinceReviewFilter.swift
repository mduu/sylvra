import Foundation

/// After a rebase (a restacked layer), comparing the last reviewed commit with the head also shows what the rebase
/// brought in from below. Files the pull request itself doesn't change can only come from there, so they are left
/// out. Files both change can still show some of it: telling those lines apart needs a range-diff.
enum SinceReviewFilter {
    /// The files of `sinceReview` the pull request changes, and how many were left out.
    static func restrict(_ sinceReview: [FileDiff], to pullRequest: [FileDiff]) -> (files: [FileDiff], hidden: Int) {
        let paths = Set(pullRequest.flatMap { [$0.path, $0.previousPath].compactMap { $0 } })
        let kept = sinceReview.filter { file in
            paths.contains(file.path) || file.previousPath.map(paths.contains) == true
        }
        return (kept, sinceReview.count - kept.count)
    }
}
