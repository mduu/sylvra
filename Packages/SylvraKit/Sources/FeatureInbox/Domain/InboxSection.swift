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

    /// What happened on the signed-in user's own pull requests since `previous`: feedback by others and
    /// checks that finished. Only pull requests `previous` already knew count (no burst after launch).
    public func ownPullRequestEvents(comparedTo previous: InboxSnapshot) -> [OwnPullRequestEvent] {
        let before = Dictionary(
            previous.pullRequests(in: .myPullRequests).map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        return pullRequests(in: .myPullRequests).flatMap { pullRequest -> [OwnPullRequestEvent] in
            guard let old = before[pullRequest.id] else { return [] }
            var events: [OwnPullRequestEvent] = []
            // A snapshot from before this was tracked knows no feedback: only what came after it counts.
            let known = old.authorFeedback?.at ?? previous.loadedAt.addingTimeInterval(-300)
            if let feedback = pullRequest.authorFeedback, feedback.at > known {
                events.append(OwnPullRequestEvent(pullRequest: pullRequest, kind: .feedback(feedback)))
            }
            if old.checkState == .pending, pullRequest.checkState != old.checkState {
                switch pullRequest.checkState {
                case .success: events.append(OwnPullRequestEvent(pullRequest: pullRequest, kind: .checksPassed))
                case .failure, .error:
                    events.append(OwnPullRequestEvent(pullRequest: pullRequest, kind: .checksFailed))
                default: break
                }
            }
            return events
        }
    }
}

/// Something the author of a pull request wants to hear about.
public struct OwnPullRequestEvent: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case feedback(AuthorFeedback)
        case checksPassed, checksFailed
    }

    public let pullRequest: PullRequestSummary
    public let kind: Kind

    public init(pullRequest: PullRequestSummary, kind: Kind) {
        self.pullRequest = pullRequest
        self.kind = kind
    }

    /// The notification's text, e.g. "@anna approved".
    public var message: String {
        switch kind {
        case .feedback(let feedback):
            let who = feedback.by.map { "@\($0)" } ?? String(localized: "Someone")
            switch feedback.kind {
            case .approved: return String(localized: "\(who) approved")
            case .changesRequested: return String(localized: "\(who) requested changes")
            case .comment: return String(localized: "\(who) commented")
            case .reviewed: return String(localized: "\(who) reviewed")
            }
        case .checksPassed: return String(localized: "Checks passed")
        case .checksFailed: return String(localized: "Checks failed")
        }
    }
}
