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

/// Loads diffs and file contents and syncs the viewed state.
public protocol DiffLoading: Sendable {
    func loadDiff(for id: PullRequestID) async throws -> PullRequestDiff
    /// Full content of a file at a commit (used for the full-file mode).
    func loadFileContent(for id: PullRequestID, path: String, ref: String) async throws -> String
    /// Marks a file as viewed / not viewed on GitHub.
    func setViewed(_ viewed: Bool, path: String, pullRequestNodeID: String) async throws
}
