import SylvraCore

/// Reads a merged pull request's way to production from GitHub and approves waiting deployments.
public protocol DeliveryLoading: Sendable {
    /// The delivery of a pull request; `nil` while it is not merged.
    func loadDelivery(for id: PullRequestID) async throws -> Delivery?
    /// Approves a deployment that waits for the signed-in user — only ever on their click.
    func approve(_ approval: DeliveryStage.Approval) async throws
}

/// Checks a stage of a delivery with an AI agent (read-only; see specs/delivery.md §3).
public protocol DeliveryVerifying: Sendable {
    func verify(_ request: VerificationRequest) async throws -> StageVerification
}

/// What the Delivery tab needs to know about the pull request to ask for a verification.
public struct DeliveryPullRequestInfo: Sendable {
    public let title: String
    public let body: String

    public init(title: String, body: String) {
        self.title = title
        self.body = body
    }
}
