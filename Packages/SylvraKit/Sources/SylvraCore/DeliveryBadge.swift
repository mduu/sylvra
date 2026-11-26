import Foundation

/// A merged pull request's way to production in short, for the inbox: a dot per stage and the outcome.
/// Filled by the app from the delivery slice; the inbox only shows it.
public struct DeliveryBadge: Hashable, Sendable {
    public enum Dot: Hashable, Sendable {
        case done, running, waiting, needsApproval, failed, skipped
    }

    public enum Outcome: Hashable, Sendable {
        /// Still on its way.
        case inProgress
        /// Live, and the AI check (where there was one) found nothing wrong.
        case healthy
        /// A stage failed or the AI check found problems.
        case problem
    }

    public let dots: [Dot]
    public let outcome: Outcome
    /// "test is running", "Live · healthy", "dev failed".
    public let text: String

    public init(dots: [Dot], outcome: Outcome, text: String) {
        self.dots = dots
        self.outcome = outcome
        self.text = text
    }
}
