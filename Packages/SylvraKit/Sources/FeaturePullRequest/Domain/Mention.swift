import Foundation
import SylvraCore

/// A place in the pull request where the signed-in user was @-mentioned.
public struct Mention: Hashable, Sendable, Identifiable {
    public enum Place: Hashable, Sendable {
        case description
        case comment
        case review
        case codeComment(path: String, line: Int?)
    }

    public let place: Place
    public let author: UserRef
    public let date: Date
    /// The paragraph containing the mention, shortened.
    public let excerpt: String
    public let url: URL?

    public init(place: Place, author: UserRef, date: Date, excerpt: String, url: URL?) {
        self.place = place
        self.author = author
        self.date = date
        self.excerpt = excerpt
        self.url = url
    }

    public var id: String { "\(url?.absoluteString ?? "")|\(date.timeIntervalSince1970)|\(excerpt.prefix(20))" }
}

/// Why the signed-in user is involved in a pull request (shown when it isn't obvious).
public struct Involvement: Hashable, Sendable {
    /// The signed-in user's login (highlighted in excerpts).
    public var login: String?
    public var mentions: [Mention]
    /// Comments and reviews the user wrote themselves.
    public var ownCommentCount: Int
    public var lastOwnCommentAt: Date?
    /// Latest commit, comment or review by someone else (bots excluded).
    public var othersLastActivityAt: Date?

    public init(
        login: String? = nil, mentions: [Mention] = [], ownCommentCount: Int = 0, lastOwnCommentAt: Date? = nil,
        othersLastActivityAt: Date? = nil
    ) {
        self.login = login
        self.mentions = mentions
        self.ownCommentCount = ownCommentCount
        self.lastOwnCommentAt = lastOwnCommentAt
        self.othersLastActivityAt = othersLastActivityAt
    }

    /// Who acted last, for "waiting on others" / "new activity".
    public var activity: ViewerActivity {
        ViewerActivity(lastActionAt: lastOwnCommentAt, othersLastActivityAt: othersLastActivityAt)
    }

    public var isEmpty: Bool { mentions.isEmpty && ownCommentCount == 0 }
}

/// Finds @-mentions of a login in Markdown text.
public enum MentionFinder {
    /// `@login` as a whole word, case-insensitive; code spans and quoted replies are ignored.
    public static func mentions(_ login: String, in text: String) -> Bool {
        excerpt(mentioning: login, in: text) != nil
    }

    /// The first paragraph mentioning the login, at most `limit` characters.
    public static func excerpt(mentioning login: String, in text: String, limit: Int = 180) -> String? {
        guard !login.isEmpty else { return nil }
        let pattern = "(?<![A-Za-z0-9_-])@" + NSRegularExpression.escapedPattern(for: login) + "(?![A-Za-z0-9_-])"
        guard let regex = try? NSRegularExpression(pattern: pattern, options: .caseInsensitive) else { return nil }
        let paragraphs = text.replacingOccurrences(of: "\r\n", with: "\n").components(separatedBy: "\n\n")
        for paragraph in paragraphs {
            let lines = paragraph.split(separator: "\n", omittingEmptySubsequences: false)
                .filter { !$0.trimmingCharacters(in: .whitespaces).hasPrefix(">") }
            let candidate = lines.joined(separator: " ")
            let withoutCode = candidate.replacingOccurrences(of: "`[^`]*`", with: "", options: .regularExpression)
            let range = NSRange(withoutCode.startIndex..., in: withoutCode)
            guard regex.firstMatch(in: withoutCode, range: range) != nil else { continue }
            let collapsed = candidate.split(whereSeparator: \.isWhitespace).joined(separator: " ")
            return collapsed.count > limit ? String(collapsed.prefix(limit - 1)) + "…" : collapsed
        }
        return nil
    }
}
