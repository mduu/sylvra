import Foundation
import Platform
import SylvraCore
import Testing

@testable import FeatureInbox

struct GitHubInboxLoaderTests {
    @Test func buildsOneAliasedSearchPerChunk() {
        let query = GitHubInboxLoader.query(searchCount: 2, pageSize: 5)
        #expect(query.hasPrefix("query($q0: String!, $q1: String!)"))
        #expect(query.contains("s1: search(query: $q1, type: ISSUE, first: 5)"))
        #expect(query.contains("fragment PR on PullRequest"))
        #expect(GitHubInboxLoader.variables(["a", "b"]) == ["q0": .string("a"), "q1": .string("b")])
    }

    @Test func scopeLimitsOnlyBroadSections() {
        let scope = InboxScope(repositories: [InboxRepository(owner: "acme", name: "billing")])
        #expect(scope.searchQueries(for: .involved).first?.hasSuffix(" repo:acme/billing") == true)
        #expect(scope.searchQueries(for: .requestedFromMe).first?.contains("repo:") == false)
        #expect(scope.searchQueries(for: .myPullRequests).first?.contains("repo:") == false)
        #expect(InboxScope.all.searchQueries(for: .myTeams).first?.contains("repo:") == false)
    }

    @Test func scopeSplitsLongRepositoryListsIntoShortQueries() {
        let repositories = (1...30).map { InboxRepository(owner: "digitec-galaxus", name: "service-number-\($0)") }
        let queries = InboxScope(repositories: repositories).searchQueries(for: .myTeams)
        #expect(queries.count > 1)
        #expect(queries.allSatisfy { $0.count <= InboxScope.maxQueryLength })
        let mentioned = queries.flatMap { $0.split(separator: " ").filter { $0.hasPrefix("repo:") } }
        #expect(mentioned.count == 30)
    }

    @Test func repositoriesCompareCaseInsensitively() {
        #expect(InboxRepository(owner: "Acme", name: "Billing") == InboxRepository(owner: "acme", name: "billing"))
    }

    @Test func recentlyClosedUsesSevenDayWindow() throws {
        let now = try Date("2026-11-15T12:00:00Z", strategy: .iso8601)
        let query = InboxSection.recentlyClosed.searchQuery(now: now)
        #expect(query.contains("is:closed closed:>=2026-11-08"))
        #expect(InboxSection.myTeams.searchQuery().hasPrefix("is:pr is:open"))
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

    @Test func scopeFiltersBroadSectionsAndPersists() async throws {
        let defaults = try #require(UserDefaults(suiteName: "InboxScopeTests-\(UUID().uuidString)"))
        let model = InboxScreenModel(
            loader: DemoInboxLoader(), repositorySearcher: DemoRepositorySearcher(), defaults: defaults)
        await model.refresh()
        #expect(model.suggestedRepositories.count == 5)

        await model.addRepository(InboxRepository(owner: "acme", name: "identity"))
        #expect(model.snapshot.pullRequests(in: .myTeams).map(\.id.repository) == ["identity"])
        #expect(model.snapshot.pullRequests(in: .requestedFromMe).count == 2)
        #expect(model.snapshot.pullRequests(in: .involved).isEmpty)
        #expect(!model.suggestedRepositories.contains(InboxRepository(owner: "acme", name: "identity")))

        let restored = InboxScreenModel(loader: DemoInboxLoader(), defaults: defaults)
        #expect(restored.scope.repositories.map(\.fullName) == ["acme/identity"])

        await model.showAllRepositories()
        #expect(model.snapshot.pullRequests(in: .myTeams).count == 3)
    }

    @Test func demoSearchFindsRepositories() async throws {
        let found = try await DemoRepositorySearcher().searchRepositories(matching: "org:acme bill")
        #expect(found.map(\.name) == ["billing", "billing-legacy"])
    }

    @Test func reportsFailures() async {
        struct Failing: InboxLoading {
            func loadInbox(scope: InboxScope) async throws -> InboxSnapshot { throw GitHubError.notAuthenticated }
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
