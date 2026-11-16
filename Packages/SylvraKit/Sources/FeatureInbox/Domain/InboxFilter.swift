import Foundation
import SylvraCore

/// Persistent filter preferences of the pull request lists.
public struct InboxFilterPreferences: Equatable, Sendable, Codable {
    /// Hide pull requests by bot accounts (Renovate, Dependabot …).
    public var hidesBots = false
    /// Hide drafts of other people; the user's own drafts always stay visible.
    public var hidesOthersDrafts = false
    /// Logins whose pull requests are hidden (lowercased, sorted).
    public private(set) var hiddenAuthors: [String] = []

    public init(hidesBots: Bool = false, hidesOthersDrafts: Bool = false, hiddenAuthors: [String] = []) {
        self.hidesBots = hidesBots
        self.hidesOthersDrafts = hidesOthersDrafts
        self.hiddenAuthors = Array(Set(hiddenAuthors.map { $0.lowercased() })).sorted()
    }

    public mutating func hideAuthor(_ login: String) {
        self = InboxFilterPreferences(
            hidesBots: hidesBots, hidesOthersDrafts: hidesOthersDrafts, hiddenAuthors: hiddenAuthors + [login])
    }

    public mutating func showAuthor(_ login: String) {
        hiddenAuthors.removeAll { $0 == login.lowercased() }
    }

    /// Number of active preferences (for the filter button badge).
    public var activeCount: Int { (hidesBots ? 1 : 0) + (hidesOthersDrafts ? 1 : 0) + hiddenAuthors.count }
}

/// Quick filters shown as chips above the list (not persisted).
public enum QuickFilter: String, CaseIterable, Identifiable, Sendable {
    /// Still waiting for an approving review.
    case needsReview
    /// CI failed.
    case ciFailing
    /// Up to size M (< 400 changed lines).
    case small

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .needsReview: String(localized: "Needs review")
        case .ciFailing: String(localized: "CI failing")
        case .small: String(localized: "Small")
        }
    }

    public var systemImage: String {
        switch self {
        case .needsReview: "eye"
        case .ciFailing: "xmark.octagon"
        case .small: "s.circle"
        }
    }

    func matches(_ pullRequest: PullRequestSummary) -> Bool {
        switch self {
        case .needsReview: pullRequest.reviewDecision == .reviewRequired
        case .ciFailing: pullRequest.checkState == .failure
        case .small: [.xs, .s, .m].contains(pullRequest.size)
        }
    }
}

/// Everything that decides whether a pull request is listed.
public struct PullRequestFilter: Equatable, Sendable {
    public var preferences = InboxFilterPreferences()
    public var quickFilters: Set<QuickFilter> = []
    /// Only pull requests of this author (login).
    public var author: String?
    /// The signed-in user, whose drafts are never hidden.
    public var viewerLogin: String?

    public init(
        preferences: InboxFilterPreferences = InboxFilterPreferences(), quickFilters: Set<QuickFilter> = [],
        author: String? = nil, viewerLogin: String? = nil
    ) {
        self.preferences = preferences
        self.quickFilters = quickFilters
        self.author = author
        self.viewerLogin = viewerLogin
    }

    /// Quick filters or an author are selected (cleared with one click).
    public var hasTemporaryFilters: Bool { !quickFilters.isEmpty || author != nil }

    public func matches(_ pullRequest: PullRequestSummary) -> Bool {
        let login = pullRequest.author.login.lowercased()
        let isMine = viewerLogin.map { $0.lowercased() == login } ?? false
        if let author, author.lowercased() != login { return false }
        if preferences.hiddenAuthors.contains(login), !isMine { return false }
        if preferences.hidesBots, pullRequest.isByBot { return false }
        if preferences.hidesOthersDrafts, pullRequest.isDraft, !isMine { return false }
        return quickFilters.allSatisfy { $0.matches(pullRequest) }
    }
}
