import Foundation
import Platform
import SylvraCore
import Testing

@testable import FeatureInbox

struct GitHubInboxLoaderTests {
    @Test func queryContainsOneAliasedSearchPerSection() {
        let query = GitHubInboxLoader.query(pageSize: 5)
        for section in InboxSection.allCases {
            #expect(query.contains("\(section.rawValue): search("))
        }
        #expect(query.contains("user-review-requested:@me"))
        #expect(query.contains("fragment PR on PullRequest"))
    }

    @Test func decodesPullRequestNode() throws {
        let json = """
            {"number": 7, "title": "Fix it", "url": "https://github.com/o/r/pull/7", "isDraft": false,
             "createdAt": "2026-11-01T10:00:00Z", "updatedAt": "2026-11-02T10:00:00Z",
             "additions": 10, "deletions": 2, "headRefName": "fix", "baseRefName": "main",
             "reviewDecision": "APPROVED", "mergeable": "CONFLICTING",
             "repository": {"name": "r", "owner": {"login": "o"}},
             "author": {"login": "ann", "avatarUrl": null, "name": "Ann Lee"},
             "commits": {"nodes": [{"commit": {"statusCheckRollup": {"state": "FAILURE"}}}]}}
            """
        let node = try GitHubJSON.decoder.decode(PullRequestNode.self, from: Data(json.utf8))
        let summary = try #require(node.summary)
        #expect(summary.id == PullRequestID(owner: "o", repository: "r", number: 7))
        #expect(summary.author.initials == "AL")
        #expect(summary.checkState == .failure)
        #expect(summary.reviewDecision == .approved)
        #expect(summary.mergeability == .conflicting)
        #expect(summary.size == .s)
    }

    @Test func ignoresNonPullRequestNodes() throws {
        let node = try GitHubJSON.decoder.decode(PullRequestNode.self, from: Data("{}".utf8))
        #expect(node.summary == nil)
    }
}

@MainActor
struct InboxScreenModelTests {
    @Test func loadsAndFilters() async {
        let model = InboxScreenModel(loader: DemoInboxLoader())
        await model.refresh()
        #expect(model.loadState == .loaded)
        #expect(model.visibleSections.count == InboxSection.allCases.count)

        model.searchText = "zzz-no-match"
        #expect(model.visibleSections.isEmpty)

        model.searchText = "passkeys"
        let visible = model.visibleSections.flatMap(\.pullRequests)
        #expect(visible.map(\.title) == ["Migrate auth to passkeys"])
    }

    @Test func reportsFailures() async {
        struct Failing: InboxLoading {
            func loadInbox() async throws -> InboxSnapshot { throw GitHubError.notAuthenticated }
        }
        let model = InboxScreenModel(loader: Failing())
        await model.refresh()
        guard case .failed = model.loadState else {
            Issue.record("expected failure state")
            return
        }
    }
}

struct ChangeSizeTests {
    @Test(arguments: [(5, ChangeSize.xs), (50, .s), (300, .m), (999, .l), (5000, .xl)])
    func sizes(lines: Int, expected: ChangeSize) {
        #expect(ChangeSize(changedLines: lines) == expected)
    }
}
