import Foundation

/// Creates the issue in Sylvra's repository — only ever on the user's click on *Send*.
public protocol FeedbackSending: Sendable {
    /// `screenshot`: PNG data to attach (`nil`: none).
    func send(_ draft: FeedbackDraft, info: SystemInfo?, screenshot: Data?) async throws -> FeedbackReceipt
}
