import Foundation
import SylvraCore

/// The smart sections of the inbox (see specs/ux.md §5).
public enum InboxSection: String, CaseIterable, Identifiable, Sendable, Codable {
    case requestedFromMe
    case myTeams
    case involved
    case myPullRequests
    case recentlyClosed

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .requestedFromMe: String(localized: "Requested from me")
        case .myTeams: String(localized: "My teams")
        case .involved: String(localized: "Involved")
        case .myPullRequests: String(localized: "My PRs")
        case .recentlyClosed: String(localized: "Recently closed")
        }
    }

    /// Full GitHub search query of the section.
    func searchQuery(now: Date = .now) -> String {
        let state: String
        if self == .recentlyClosed {
            let since = Calendar.current.date(byAdding: .day, value: -7, to: now) ?? now
            state = "is:closed closed:>=\(since.formatted(.iso8601.year().month().day()))"
        } else {
            state = "is:open"
        }
        return "is:pr \(state) archived:false sort:updated-desc \(searchQualifiers)"
    }

    /// Section-specific qualifiers.
    var searchQualifiers: String {
        switch self {
        case .requestedFromMe: "user-review-requested:@me"
        case .myTeams: "review-requested:@me -user-review-requested:@me"
        case .involved: "involves:@me -author:@me -review-requested:@me"
        case .myPullRequests: "author:@me"
        case .recentlyClosed: "involves:@me"
        }
    }
}

/// Result of loading the inbox.
public struct InboxSnapshot: Sendable, Equatable, Codable {
    public var sections: [InboxSection: [PullRequestSummary]]
    public var loadedAt: Date
    /// Some organizations hid their results because the token lacks SSO authorization (`nil` = no).
    public var isRestrictedBySSO: Bool?
    /// Login of the signed-in user (own drafts always stay visible).
    public var viewerLogin: String?

    public init(
        sections: [InboxSection: [PullRequestSummary]], loadedAt: Date = .now, isRestrictedBySSO: Bool? = nil,
        viewerLogin: String? = nil
    ) {
        self.sections = sections
        self.loadedAt = loadedAt
        self.isRestrictedBySSO = isRestrictedBySSO
        self.viewerLogin = viewerLogin
    }

    public func pullRequests(in section: InboxSection) -> [PullRequestSummary] {
        sections[section] ?? []
    }

    public var isEmpty: Bool { sections.values.allSatisfy(\.isEmpty) }

    /// Same pull requests and flags; only `loadedAt` may differ.
    public func hasSameContent(as other: InboxSnapshot) -> Bool {
        sections == other.sections && isRestrictedBySSO == other.isRestrictedBySSO && viewerLogin == other.viewerLogin
    }

    /// Pull requests where someone else acted after the reviewer's last comment or review, and that activity
    /// is newer than in `previous`. Only pull requests `previous` already knew count (no burst after launch).
    public func newActivity(comparedTo previous: InboxSnapshot) -> [PullRequestSummary] {
        let before = Dictionary(
            previous.sections.values.joined().map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var seen = Set<PullRequestID>()
        return InboxSection.allCases.filter { $0 != .recentlyClosed }.flatMap { pullRequests(in: $0) }
            .filter { pullRequest in
                guard seen.insert(pullRequest.id).inserted, let activity = pullRequest.viewerActivity,
                    activity.hasNewActivity, let others = activity.othersLastActivityAt,
                    let old = before[pullRequest.id]
                else { return false }
                return others > (old.viewerActivity?.othersLastActivityAt ?? .distantFuture)
            }
    }
}
