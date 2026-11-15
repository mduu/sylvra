import Foundation
import SylvraCore

/// The smart sections of the inbox (see specs/ux.md §5).
public enum InboxSection: String, CaseIterable, Identifiable, Sendable {
    case requestedFromMe
    case myTeams
    case involved
    case myPullRequests

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .requestedFromMe: String(localized: "Requested from me")
        case .myTeams: String(localized: "My teams")
        case .involved: String(localized: "Involved")
        case .myPullRequests: String(localized: "My PRs")
        }
    }

    /// GitHub search qualifiers for the section (open, non-archived PRs are added by the loader).
    var searchQualifiers: String {
        switch self {
        case .requestedFromMe: "user-review-requested:@me"
        case .myTeams: "review-requested:@me -user-review-requested:@me"
        case .involved: "involves:@me -author:@me -review-requested:@me"
        case .myPullRequests: "author:@me"
        }
    }
}

/// Result of loading the inbox.
public struct InboxSnapshot: Sendable, Equatable {
    public var sections: [InboxSection: [PullRequestSummary]]
    public var loadedAt: Date

    public init(sections: [InboxSection: [PullRequestSummary]], loadedAt: Date = .now) {
        self.sections = sections
        self.loadedAt = loadedAt
    }

    public func pullRequests(in section: InboxSection) -> [PullRequestSummary] {
        sections[section] ?? []
    }

    public var isEmpty: Bool { sections.values.allSatisfy(\.isEmpty) }
}
