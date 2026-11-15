import Foundation

/// Loads the pull requests shown in the inbox.
public protocol InboxLoading: Sendable {
    func loadInbox() async throws -> InboxSnapshot
}
