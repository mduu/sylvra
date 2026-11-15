import SylvraCore

/// Loads the full details of one pull request.
public protocol PullRequestDetailLoading: Sendable {
    func loadDetail(for id: PullRequestID) async throws -> PullRequestDetail
}
