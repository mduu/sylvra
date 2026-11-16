import Foundation
import SylvraCore

/// A comment of the pull request for the Comments tab: a general comment, a review summary, or a code
/// discussion (thread) with its replies.
public struct DiscussionItem: Identifiable, Hashable, Sendable {
    public enum Place: Hashable, Sendable {
        /// A comment on the pull request itself.
        case conversation
        /// The text of a submitted review.
        case review
        /// A thread on code; `line` is `nil` when the code changed since (outdated).
        case code(path: String, line: Int?, isResolved: Bool)
    }

    public let id: String
    public let place: Place
    public let author: UserRef
    public let body: String
    public let date: Date
    public let url: URL?
    /// Further comments of a code thread, oldest first.
    public let replies: [Reply]

    public struct Reply: Hashable, Sendable {
        public let author: UserRef
        public let body: String
        public let date: Date

        public init(author: UserRef, body: String, date: Date) {
            self.author = author
            self.body = body
            self.date = date
        }
    }

    public init(
        id: String, place: Place, author: UserRef, body: String, date: Date, url: URL? = nil, replies: [Reply] = []
    ) {
        self.id = id
        self.place = place
        self.author = author
        self.body = body
        self.date = date
        self.url = url
        self.replies = replies
    }

    /// Latest activity: the last reply or the comment itself.
    public var lastActivity: Date { replies.last?.date ?? date }

    /// Where a code comment sits, for jumping to it (`nil` for general comments).
    public var codeLocation: (path: String, line: Int?)? {
        if case .code(let path, let line, _) = place { return (path, line) }
        return nil
    }

    public var isResolved: Bool {
        if case .code(_, _, let resolved) = place { return resolved }
        return false
    }

    /// Number of comments, replies included.
    public var commentCount: Int { 1 + replies.count }
}

/// Filters of the Comments tab.
public enum DiscussionFilter: String, CaseIterable, Identifiable, Sendable {
    case all, code, general, open

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .all: String(localized: "All")
        case .code: String(localized: "Code")
        case .general: String(localized: "General")
        case .open: String(localized: "Unresolved")
        }
    }

    /// Matching items, latest activity first.
    public func apply(_ items: [DiscussionItem]) -> [DiscussionItem] {
        items.filter { item in
            switch self {
            case .all: true
            case .code: item.codeLocation != nil
            case .general: item.codeLocation == nil
            case .open: item.codeLocation != nil && !item.isResolved
            }
        }
        .sorted { $0.lastActivity > $1.lastActivity }
    }
}
