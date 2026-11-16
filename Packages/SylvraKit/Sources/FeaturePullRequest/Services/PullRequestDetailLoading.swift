import SylvraCore

/// Loads the full details of one pull request.
public protocol PullRequestDetailLoading: Sendable {
    func loadDetail(for id: PullRequestID) async throws -> PullRequestDetail
    /// The summary and annotations of one check run (loaded when the reviewer opens it).
    func loadCheckReport(nodeID: String) async throws -> CheckReport
}

extension PullRequestDetailLoading {
    public func loadCheckReport(nodeID: String) async throws -> CheckReport { CheckReport() }
}
