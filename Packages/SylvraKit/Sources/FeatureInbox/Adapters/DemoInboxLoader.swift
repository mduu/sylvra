import Foundation
import SylvraCore

/// Fixture data for screenshots, previews and the `--demo` launch argument.
public struct DemoInboxLoader: InboxLoading {
    public init() {}

    public func loadInbox() async throws -> InboxSnapshot {
        InboxSnapshot(sections: Self.sections)
    }

    public static let sections: [InboxSection: [PullRequestSummary]] = [
        .requestedFromMe: [
            pr(
                "billing", 1234, "Add invoice export", "lkeller", "Lena Keller", hoursAgo: 2, 182, 41, .success,
                .reviewRequired),
            pr(
                "payments", 881, "Retry failed webhooks with backoff", "jmeier", "Jonas Meier", hoursAgo: 5, 64, 12,
                .pending),
        ],
        .myTeams: [
            pr("identity", 412, "Migrate auth to passkeys", "srossi", "Sara Rossi", hoursAgo: 26, 930, 610, .failure),
            pr("ios-app", 2201, "Bump SwiftLint to 0.65", "dbrunner", "David Brunner", hoursAgo: 30, 3, 3, .success),
            pr(
                "catalog", 77, "Cache product images on disk", "anovak", "Ana Novak", hoursAgo: 52, 210, 18, .success,
                draft: true),
        ],
        .involved: [
            pr(
                "billing", 1229, "Split pricing module", "twagner", "Tim Wagner", hoursAgo: 75, 420, 388, .success,
                .approved)
        ],
        .myPullRequests: [
            pr(
                "billing", 1240, "Feature flags for exports", "mduu", "Marc Dürst", hoursAgo: 8, 96, 20, .success,
                .changesRequested)
        ],
        .recentlyClosed: [
            pr("billing", 812, "Fix VAT rounding", "lkeller", "Lena Keller", hoursAgo: 120, 34, 12, .success, .approved)
        ],
    ]

    // swiftlint:disable:next function_parameter_count
    static func pr(
        _ repository: String,
        _ number: Int,
        _ title: String,
        _ login: String,
        _ name: String,
        hoursAgo: Double,
        _ additions: Int,
        _ deletions: Int,
        _ checks: CheckState,
        _ review: ReviewDecision = .reviewRequired,
        draft: Bool = false
    ) -> PullRequestSummary {
        let updated = Date.now.addingTimeInterval(-hoursAgo * 3600)
        return PullRequestSummary(
            id: PullRequestID(owner: "acme", repository: repository, number: number),
            title: title,
            author: UserRef(login: login, name: name),
            url: URL(string: "https://github.com/acme/\(repository)/pull/\(number)"),
            isDraft: draft,
            createdAt: updated.addingTimeInterval(-86_400),
            updatedAt: updated,
            additions: additions,
            deletions: deletions,
            headRefName: "feature/\(title.lowercased().split(separator: " ").prefix(2).joined(separator: "-"))",
            baseRefName: "main",
            checkState: checks,
            reviewDecision: review,
            mergeability: .mergeable
        )
    }
}
