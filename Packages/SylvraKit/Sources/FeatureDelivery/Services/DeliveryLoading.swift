import SylvraCore

/// Reads a merged pull request's way to production from GitHub and approves waiting deployments.
public protocol DeliveryLoading: Sendable {
    /// The delivery of a pull request; `nil` while it is not merged.
    func loadDelivery(for id: PullRequestID) async throws -> Delivery?
    /// Approves a deployment that waits for the signed-in user — only ever on their click.
    func approve(_ approval: DeliveryStage.Approval) async throws
}
