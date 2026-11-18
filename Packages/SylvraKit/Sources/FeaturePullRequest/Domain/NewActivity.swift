import Foundation
import SylvraCore

/// What others did on a pull request after the signed-in user's last comment or review: new commits and
/// new comments, reviews and replies (bots excluded).
public struct NewActivity: Hashable, Sendable {
    /// A comment, review text or reply by someone else.
    public struct Comment: Hashable, Sendable, Identifiable {
        public let id: String
        public let author: UserRef
        public let place: DiscussionItem.Place
        /// An answer in a code thread (not its first comment).
        public let isReply: Bool
        public let excerpt: String
        public let date: Date
        public let url: URL?
    }

    /// The user's last comment or review: everything here happened after it.
    public let since: Date
    /// New commits, newest first.
    public let commits: [Commit]
    /// New comments, newest first.
    public let comments: [Comment]

    public var isEmpty: Bool { commits.isEmpty && comments.isEmpty }

    /// What happened in `detail` after `since`, leaving out the viewer's own and bots' activity.
    public static func since(_ since: Date, in detail: PullRequestDetail, viewer login: String?) -> NewActivity {
        func isOther(_ user: UserRef) -> Bool {
            let author = user.login.lowercased()
            return author != login?.lowercased() && !author.hasSuffix("[bot]")
        }
        let commits = detail.commits.filter { $0.authoredAt > since }.sorted { $0.authoredAt > $1.authoredAt }
        var comments: [Comment] = []
        for item in detail.discussion {
            if item.date > since, isOther(item.author) {
                comments.append(
                    Comment(
                        id: item.id, author: item.author, place: item.place, isReply: false,
                        excerpt: excerpt(item.body), date: item.date, url: item.url))
            }
            for (index, reply) in item.replies.enumerated() where reply.date > since && isOther(reply.author) {
                comments.append(
                    Comment(
                        id: "\(item.id)#\(index)", author: reply.author, place: item.place, isReply: true,
                        excerpt: excerpt(reply.body), date: reply.date, url: item.url))
            }
        }
        return NewActivity(since: since, commits: commits, comments: comments.sorted { $0.date > $1.date })
    }

    /// The text without quoted replies, on one line, at most `limit` characters.
    static func excerpt(_ body: String, limit: Int = 160) -> String {
        let lines = body.replacingOccurrences(of: "\r\n", with: "\n").split(separator: "\n")
            .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }
        let text = lines.joined(separator: " ").split(whereSeparator: \.isWhitespace).joined(separator: " ")
        return text.count > limit ? String(text.prefix(limit - 1)) + "…" : text
    }
}

extension PullRequestDetail {
    /// What others did after the user's last comment or review; `nil` when the user never took part or
    /// nothing happened since.
    public var newActivity: NewActivity? {
        guard involvement.activity.hasNewActivity, let since = involvement.lastOwnCommentAt else { return nil }
        let activity = NewActivity.since(since, in: self, viewer: involvement.login)
        return activity.isEmpty ? nil : activity
    }
}
