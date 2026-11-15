import Foundation
import SylvraCore

/// The diff of a pull request plus the reviewer's viewed state.
public struct PullRequestDiff: Sendable, Equatable {
    public var files: [FileDiff]
    public var viewedPaths: Set<String>
    /// GitHub node ID, needed for the viewed-state mutations.
    public var nodeID: String?

    public init(files: [FileDiff], viewedPaths: Set<String> = [], nodeID: String? = nil) {
        self.files = files
        self.viewedPaths = viewedPaths
        self.nodeID = nodeID
    }
}

/// Where the PR stands for the reviewer: current head and the commit of the reviewer's last review.
public struct ReviewProgress: Sendable, Equatable {
    public var headSHA: String
    /// Commit the reviewer's latest submitted review was made on; `nil` if they never reviewed.
    public var lastReviewedSHA: String?
    public var lastReviewedAt: Date?

    public init(headSHA: String, lastReviewedSHA: String? = nil, lastReviewedAt: Date? = nil) {
        self.headSHA = headSHA
        self.lastReviewedSHA = lastReviewedSHA
        self.lastReviewedAt = lastReviewedAt
    }

    /// The PR has commits the reviewer hasn't reviewed yet.
    public var hasChangesSinceReview: Bool { lastReviewedSHA.map { $0 != headSHA } ?? false }
}

/// Loads diffs and file contents and syncs the viewed state.
public protocol DiffLoading: Sendable {
    func loadDiff(for id: PullRequestID) async throws -> PullRequestDiff
    /// Full content of a file at a commit (used for the full-file mode).
    func loadFileContent(for id: PullRequestID, path: String, ref: String) async throws -> String
    /// Marks a file as viewed / not viewed on GitHub.
    func setViewed(_ viewed: Bool, path: String, pullRequestNodeID: String) async throws
    /// Current head and the reviewer's last reviewed commit (polled to detect new pushes).
    func loadReviewProgress(for id: PullRequestID) async throws -> ReviewProgress
    /// Diff between two commits of the PR (e.g. last reviewed commit → head).
    func loadDiff(for id: PullRequestID, from base: String, to head: String) async throws -> [FileDiff]
}
