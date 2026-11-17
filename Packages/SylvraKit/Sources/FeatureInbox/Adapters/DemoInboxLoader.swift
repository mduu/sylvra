import Foundation
import SylvraCore

/// Fixture data for screenshots, previews and the `--demo` launch argument.
public struct DemoInboxLoader: InboxLoading {
    public init() {}

    public func loadInbox(scope: InboxScope) async throws -> InboxSnapshot {
        var sections = Self.sections
        for section in InboxSection.allCases where section.followsScope && !scope.isAll {
            sections[section] = sections[section]?.filter {
                scope.contains(owner: $0.id.owner, name: $0.id.repository)
            }
        }
        return InboxSnapshot(sections: sections, viewerLogin: "mduu")
    }

    public static let sections: [InboxSection: [PullRequestSummary]] = [
        .requestedFromMe: [
            pr(
                "billing", 1234, "Add invoice export", "lkeller", "Lena Keller", hoursAgo: 2, 182, 41, .success,
                .reviewRequired),
            pr(
                "payments", 881,
                "Retry failed webhooks with exponential backoff and move permanent failures to a dead-letter queue",
                "jmeier", "Jonas Meier", hoursAgo: 5, 64, 12,
                .pending),
        ],
        .myTeams: [
            pr("identity", 412, "Migrate auth to passkeys", "srossi", "Sara Rossi", hoursAgo: 26, 930, 610, .failure),
            pr("ios-app", 2201, "Bump SwiftLint to 0.65", "dbrunner", "David Brunner", hoursAgo: 30, 3, 3, .success),
            pr(
                "payments", 902, "Update dependency stripe to v14", "dg-renovate", "Renovate", hoursAgo: 40, 12, 9,
                .success),
            pr(
                "catalog", 77, "Cache product images on disk", "anovak", "Ana Novak", hoursAgo: 52, 210, 18, .success,
                draft: true),
        ],
        .involved: [
            pr(
                "billing", 1229, "Split pricing module", "twagner", "Tim Wagner", hoursAgo: 75, 420, 388, .success,
                .approved, respondedHoursAgo: 20)
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
        draft: Bool = false,
        respondedHoursAgo: Double? = nil
    ) -> PullRequestSummary {
        let updated = Date.now.addingTimeInterval(-hoursAgo * 3600)
        // The reviewer's last comment; others were last active at `updated`.
        let activity = respondedHoursAgo.map {
            ViewerActivity(lastActionAt: Date.now.addingTimeInterval(-$0 * 3600), othersLastActivityAt: updated)
        }
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
            mergeability: .mergeable,
            viewerActivity: activity,
            commentCount: (number * 7) % 13
        )
    }
}

/// Fixture repository search for demo mode and previews.
public struct DemoRepositorySearcher: RepositorySearching {
    public init() {}

    public static let repositories: [InboxRepository] = [
        InboxRepository(owner: "acme", name: "billing", summary: "Invoices, pricing and VAT"),
        InboxRepository(owner: "acme", name: "billing-legacy", summary: "Old billing system (read-only)"),
        InboxRepository(owner: "acme", name: "payments", summary: "Payment providers and webhooks"),
        InboxRepository(owner: "acme", name: "identity", summary: "Sign-in, passkeys and sessions"),
        InboxRepository(owner: "acme", name: "catalog", summary: "Products, images and search"),
        InboxRepository(owner: "acme", name: "ios-app", summary: "The iOS app"),
    ]

    public func searchRepositories(matching text: String) async throws -> [InboxRepository] {
        let words = text.split(separator: " ").filter { !$0.contains(":") }
        return Self.repositories.filter { repository in
            words.allSatisfy { repository.fullName.localizedCaseInsensitiveContains($0) }
        }
    }
}

/// Fixture pull requests per repository for demo mode (paged like GitHub).
public struct DemoRepositoryPullRequestLoader: RepositoryPullRequestLoading {
    private let pageSize: Int

    public init(pageSize: Int = 15) {
        self.pageSize = pageSize
    }

    static let openCounts = ["billing": 38, "payments": 12, "identity": 6, "catalog": 5, "ios-app": 9]

    private static let titles = [
        "Refactor tax calculation", "Add retry to export job", "Update dependency swift-nio to v2.80",
        "Fix flaky invoice test", "Remove legacy PDF renderer", "Log export duration", "Translate emails to French",
        "Speed up customer lookup", "Use new pricing API", "Clean up feature flags",
    ]
    private static let people = [
        ("lkeller", "Lena Keller"), ("twagner", "Tim Wagner"), ("dg-renovate", "Renovate"), ("srossi", "Sara Rossi"),
        ("mduu", "Marc Dürst"), ("anovak", "Ana Novak"),
    ]

    public func openPullRequestCounts(for repositories: [InboxRepository]) async throws -> [String: Int] {
        Dictionary(uniqueKeysWithValues: repositories.map { ($0.id, Self.openCounts[$0.name] ?? 0) })
    }

    public func loadPullRequests(
        in repository: InboxRepository, matching text: String, excludingAuthors excludedAuthors: [String],
        after cursor: String?
    ) async throws -> RepositoryPullRequestPage {
        let all = Self.pullRequests(in: repository).filter { pullRequest in
            !excludedAuthors.contains(pullRequest.author.login.lowercased())
                && (text.isEmpty || pullRequest.title.localizedCaseInsensitiveContains(text))
        }
        let start = cursor.flatMap(Int.init) ?? 0
        let end = min(start + pageSize, all.count)
        return RepositoryPullRequestPage(
            pullRequests: Array(all[start..<end]), totalCount: all.count, nextCursor: end < all.count ? "\(end)" : nil)
    }

    /// Every sixth generated PR waits on others (the reviewer responded after the last activity), the one
    /// three later has new activity after the reviewer's comment.
    static func respondedHoursAgo(index: Int, hoursAgo: Double) -> Double? {
        switch index % 6 {
        case 1: max(hoursAgo - 4, 1)
        case 4: hoursAgo + 6
        default: nil
        }
    }

    static func pullRequests(in repository: InboxRepository) -> [PullRequestSummary] {
        let known = DemoInboxLoader.sections.values.joined().filter {
            $0.id.repository == repository.name && $0.id.number != 812
        }
        let count = max((openCounts[repository.name] ?? 0) - known.count, 0)
        let generated = (0..<count).map { index in
            let person = people[index % people.count]
            let isDraft = index % 7 == 3
            return DemoInboxLoader.pr(
                repository.name, 1299 - index * 3, titles[index % titles.count], person.0, person.1,
                hoursAgo: Double(10 + index * 9), 20 + index * 17 % 400, index * 7 % 90,
                index % 5 == 2 ? .failure : .success, index % 4 == 0 ? .approved : .reviewRequired, draft: isDraft,
                respondedHoursAgo: Self.respondedHoursAgo(index: index, hoursAgo: Double(10 + index * 9)))
        }
        return (Array(known) + generated).sorted { $0.updatedAt > $1.updatedAt }
    }
}
