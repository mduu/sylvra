import Foundation

/// Who acted last on a pull request: the signed-in reviewer or someone else.
///
/// Lets the inbox show pull requests where the reviewer already commented or reviewed and nothing happened
/// since ("waiting on others") apart from ones with new activity after the reviewer's last action.
public struct ViewerActivity: Hashable, Sendable, Codable {
    /// The reviewer's last review or comment (`nil`: never took part).
    public let lastActionAt: Date?
    /// The latest commit, review or comment by someone else (bots don't count).
    public let othersLastActivityAt: Date?

    public init(lastActionAt: Date?, othersLastActivityAt: Date?) {
        self.lastActionAt = lastActionAt
        self.othersLastActivityAt = othersLastActivityAt
    }

    /// The reviewer acted last: nothing to do until someone else responds.
    public var isWaitingOnOthers: Bool {
        guard let lastActionAt else { return false }
        return (othersLastActivityAt ?? .distantPast) <= lastActionAt
    }

    /// Someone else did something after the reviewer's last review or comment.
    public var hasNewActivity: Bool {
        guard let lastActionAt, let othersLastActivityAt else { return false }
        return othersLastActivityAt > lastActionAt
    }
}
