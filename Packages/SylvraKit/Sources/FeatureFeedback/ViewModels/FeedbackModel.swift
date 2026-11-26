import Foundation
import Observation

/// State of the feedback window: the draft, the optional screenshot and what came of sending.
@MainActor
@Observable
public final class FeedbackModel {
    public enum State: Equatable {
        case editing, sending
        case sent(FeedbackReceipt)
        case failed(String)
    }

    public var draft = FeedbackDraft()
    public private(set) var state: State = .editing
    /// The picture of Sylvra's window taken when the feedback window opened (PNG).
    public private(set) var screenshot: Data?
    public private(set) var info: SystemInfo?

    private let sender: any FeedbackSending
    /// Collects the version information (wired by the app).
    @ObservationIgnored public var systemInfo: (() async -> SystemInfo)?

    public init(sender: any FeedbackSending) {
        self.sender = sender
    }

    /// A new feedback: an empty draft (kept while a draft is being written) and a fresh picture.
    public func begin(screenshot: Data?) async {
        if case .sent = state { draft = FeedbackDraft() }
        if state != .sending { state = .editing }
        self.screenshot = screenshot
        if screenshot == nil { draft.includesScreenshot = false }
        info = await systemInfo?()
    }

    public var isSending: Bool { state == .sending }

    /// Creates the issue (the user's click on *Send*).
    public func send() async {
        guard draft.canSend, state != .sending else { return }
        state = .sending
        do {
            let receipt = try await sender.send(
                draft, info: draft.includesSystemInfo ? info : nil,
                screenshot: draft.includesScreenshot ? screenshot : nil)
            state = .sent(receipt)
        } catch {
            state = .failed((error as? LocalizedError)?.errorDescription ?? String(describing: error))
        }
    }

    /// Back to the form after a failure.
    public func edit() {
        if state != .sending { state = .editing }
    }
}
