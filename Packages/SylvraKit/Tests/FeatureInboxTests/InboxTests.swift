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

    /// Regression: PRs where the reviewer commented last looked like any other open PR.
    @Test func decodesWhoActedLast() throws {
        func node(_ extra: String) throws -> PullRequestSummary? {
            let json = """
                {"number": 7, "title": "Fix it", "createdAt": "2026-11-01T10:00:00Z",
                 "updatedAt": "2026-11-02T10:00:00Z", "repository": {"name": "r", "owner": {"login": "o"}},
                 \(extra)}
                """
            return try GitHubJSON.decoder.decode(PullRequestNode.self, from: Data(json.utf8)).summary
        }
        let waiting = try node(
            """
            "viewerDidAuthor": false,
            "commits": {"nodes": [{"commit": {"committedDate": "2026-11-01T12:00:00Z"}}]},
            "comments": {"nodes": [
              {"createdAt": "2026-11-02T09:00:00Z", "viewerDidAuthor": true, "author": {"__typename": "User"}},
              {"createdAt": "2026-11-02T11:00:00Z", "viewerDidAuthor": false, "author": {"__typename": "Bot"}}]},
            "reviews": {"nodes": [
              {"submittedAt": "2026-11-01T15:00:00Z", "viewerDidAuthor": false, "author": {"__typename": "User"}},
              {"submittedAt": null, "viewerDidAuthor": true, "author": {"__typename": "User"}}]}
            """)
        #expect(waiting?.isWaitingOnOthers == true)
        let answered = try node(
            """
            "viewerDidAuthor": false,
            "commits": {"nodes": [{"commit": {"committedDate": "2026-11-02T12:00:00Z"}}]},
            "comments": {"nodes": [
              {"createdAt": "2026-11-02T09:00:00Z", "viewerDidAuthor": true, "author": {"__typename": "User"}}]}
            """)
        #expect(answered?.isWaitingOnOthers == false)
        #expect(answered?.viewerActivity?.hasNewActivity == true)
        let counted = try node(
            #""comments": {"totalCount": 4, "nodes": []}, "reviewThreads": {"totalCount": 3}"#)
        #expect(counted?.commentCount == 7)
        #expect(try node(#""viewerDidAuthor": false"#)?.commentCount == nil)
        let own = try node(#""viewerDidAuthor": true, "comments": {"nodes": []}"#)
        #expect(own?.viewerActivity == nil)
    }

    @Test func movesWaitingPullRequestsToTheEndExceptPersonalRequests() {
        let now = Date.now
        let waiting = ViewerActivity(lastActionAt: now, othersLastActivityAt: now.addingTimeInterval(-60))
        let first = DemoInboxLoader.pr("r", 1, "A", "ann", "Ann", hoursAgo: 1, 1, 1, .success, respondedHoursAgo: 0)
        let second = DemoInboxLoader.pr("r", 2, "B", "bob", "Bob", hoursAgo: 2, 1, 1, .success)
        #expect(first.isWaitingOnOthers)
        #expect(waiting.isWaitingOnOthers && !waiting.hasNewActivity)
        #expect(InboxScreenModel.waitingLast([first, second], in: .involved).map(\.id.number) == [2, 1])
        #expect(InboxScreenModel.waitingLast([first, second], in: .requestedFromMe).map(\.id.number) == [1, 2])
    }

    /// Notifications: only pull requests whose activity after the reviewer's comment is new since the last refresh.
    @Test func findsNewActivityAfterTheReviewersComment() {
        let now = Date.now
        func pr(_ number: Int, others: Date?, mine: Date? = now.addingTimeInterval(-3_600)) -> PullRequestSummary {
            let base = DemoInboxLoader.pr("r", number, "PR", "ann", "Ann", hoursAgo: 1, 1, 1, .success)
            return PullRequestSummary(
                id: base.id, title: base.title, author: base.author, createdAt: base.createdAt,
                updatedAt: base.updatedAt, additions: 1, deletions: 1, headRefName: "", baseRefName: "",
                viewerActivity: ViewerActivity(lastActionAt: mine, othersLastActivityAt: others))
        }
        let before = InboxSnapshot(sections: [
            .involved: [pr(1, others: now.addingTimeInterval(-7_200)), pr(2, others: now.addingTimeInterval(-60))]
        ])
        let after = InboxSnapshot(sections: [
            .involved: [
                pr(1, others: now), pr(2, others: now.addingTimeInterval(-60)), pr(3, others: now),
            ]
        ])
        #expect(after.newActivity(comparedTo: before).map(\.id.number) == [1])
        #expect(after.newActivity(comparedTo: InboxSnapshot(sections: [:])).isEmpty)
        #expect(before.hasSameContent(as: InboxSnapshot(sections: before.sections, loadedAt: .distantFuture)))
        #expect(!after.hasSameContent(as: before))
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
        #expect(model.snapshot.pullRequests(in: .myTeams).count == 4)
    }

    @Test func demoSearchFindsRepositories() async throws {
        let found = try await DemoRepositorySearcher().searchRepositories(matching: "org:acme bill")
        #expect(found.map(\.name) == ["billing", "billing-legacy"])
    }

    @Test @MainActor func showsRefreshingWhileLoading() async {
        actor Gate {
            var continuation: CheckedContinuation<Void, Never>?
            func wait() async { await withCheckedContinuation { continuation = $0 } }
            func open() { continuation?.resume() }
            var isWaiting: Bool { continuation != nil }
        }
        struct Gated: InboxLoading {
            let gate: Gate
            func loadInbox(scope: InboxScope) async throws -> InboxSnapshot {
                await gate.wait()
                return try await DemoInboxLoader().loadInbox(scope: scope)
            }
        }
        let gate = Gate()
        let model = InboxScreenModel(loader: Gated(gate: gate))
        #expect(!model.isRefreshing)
        let refresh = Task { await model.refreshAll() }
        while await !gate.isWaiting { await Task.yield() }
        #expect(model.isRefreshing)
        await gate.open()
        await refresh.value
        #expect(!model.isRefreshing)
        #expect(model.loadState == .loaded)
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

struct InboxFilterTests {
    private func pr(
        _ login: String, draft: Bool = false, bot: Bool = false, checks: CheckState = .success,
        review: ReviewDecision = .reviewRequired, lines: Int = 20
    ) -> PullRequestSummary {
        PullRequestSummary(
            id: PullRequestID(owner: "o", repository: "r", number: Int.random(in: 1...99_999)), title: "t",
            author: UserRef(login: login), isDraft: draft, createdAt: .now, updatedAt: .now, additions: lines,
            deletions: 0, headRefName: "h", baseRefName: "main", checkState: checks, reviewDecision: review,
            authorIsBot: bot)
    }

    @Test func detectsBots() {
        #expect(pr("dg-renovate").isByBot)
        #expect(pr("dependabot[bot]").isByBot)
        #expect(pr("release-bot").isByBot)
        #expect(pr("github-actions", bot: true).isByBot)
        #expect(!pr("lkeller").isByBot)
        #expect(!pr("robert").isByBot)
    }

    @Test func hidesBotsAuthorsAndOthersDrafts() {
        var filter = PullRequestFilter(viewerLogin: "mduu")
        filter.preferences.hidesBots = true
        filter.preferences.hidesOthersDrafts = true
        filter.preferences.hideAuthor("TWagner")
        #expect(!filter.matches(pr("dg-renovate")))
        #expect(!filter.matches(pr("lkeller", draft: true)))
        #expect(filter.matches(pr("mduu", draft: true)))
        #expect(!filter.matches(pr("twagner")))
        #expect(filter.matches(pr("lkeller")))
        filter.preferences.showAuthor("twagner")
        #expect(filter.matches(pr("twagner")))
    }

    @Test func quickFiltersAndAuthorCombine() {
        let filter = PullRequestFilter(quickFilters: [.ciFailing, .small], author: "lkeller")
        #expect(filter.matches(pr("lkeller", checks: .failure)))
        #expect(!filter.matches(pr("lkeller", checks: .failure, lines: 900)))
        #expect(!filter.matches(pr("lkeller")))
        #expect(!filter.matches(pr("srossi", checks: .failure)))
        #expect(filter.hasTemporaryFilters)
    }

    @MainActor
    @Test func modelPersistsPreferencesAndCountsHidden() async throws {
        let defaults = try #require(UserDefaults(suiteName: "InboxFilterTests-\(UUID().uuidString)"))
        let model = InboxScreenModel(loader: DemoInboxLoader(), defaults: defaults)
        await model.refresh()
        #expect(model.hiddenCount == 0)
        model.updatePreferences { $0.hidesBots = true }
        #expect(model.hiddenCount == 1)
        #expect(!model.visibleSections.flatMap(\.pullRequests).contains { $0.author.login == "dg-renovate" })
        model.showOnly(author: "lkeller")
        #expect(Set(model.visibleSections.flatMap(\.pullRequests).map(\.author.login)) == ["lkeller"])
        model.clearTemporaryFilters()
        let restored = InboxScreenModel(loader: DemoInboxLoader(), defaults: defaults)
        #expect(restored.filter.preferences.hidesBots)
    }
}

@MainActor
struct RepositoryBrowserTests {
    private let billing = InboxRepository(owner: "acme", name: "billing")

    @Test func pagesThroughAllOpenPullRequests() async {
        let browser = RepositoryBrowserModel(repository: billing, loader: DemoRepositoryPullRequestLoader(pageSize: 15))
        await browser.load(matching: "", excludingAuthors: [])
        #expect(browser.totalCount == 38)
        #expect(browser.pullRequests.count == 15)
        await browser.loadMore(excludingAuthors: [])
        await browser.loadMore(excludingAuthors: [])
        #expect(browser.pullRequests.count == 38)
        #expect(!browser.canLoadMore)
        #expect(Set(browser.pullRequests.map(\.id)).count == 38)
    }

    @Test func searchesAndExcludesHiddenAuthors() async {
        let browser = RepositoryBrowserModel(repository: billing, loader: DemoRepositoryPullRequestLoader())
        await browser.load(matching: "tax", excludingAuthors: ["mduu"])
        #expect(!browser.pullRequests.isEmpty)
        #expect(browser.pullRequests.allSatisfy { $0.title.localizedCaseInsensitiveContains("tax") })
        #expect(!browser.pullRequests.contains { $0.author.login == "mduu" })
    }

    @Test func groupsByWaitingYoursAndOpen() async {
        let model = InboxScreenModel(loader: DemoInboxLoader(), repositoryLoader: DemoRepositoryPullRequestLoader())
        await model.refresh()
        model.openRepository(billing)
        await model.browser?.load(matching: "", excludingAuthors: [])
        let groups = model.browserGroups
        #expect(groups.map(\.title) == ["Waiting for you", "Yours", "Open", "Waiting on others"])
        let waitingFlags = groups[3].pullRequests.map(\.isWaitingOnOthers)
        let openFlags = groups[2].pullRequests.map(\.isWaitingOnOthers)
        #expect(!waitingFlags.contains(false))
        #expect(!openFlags.contains(true))
        #expect(groups[0].pullRequests.map(\.id.number) == [1234])
        #expect(groups[1].pullRequests.allSatisfy { $0.author.login == "mduu" })
        #expect(model.summary(for: groups[2].pullRequests[0].id) != nil)
        model.closeRepository()
        #expect(model.browser == nil)
    }

    @Test func persistsCollapsedSections() throws {
        let defaults = try #require(UserDefaults(suiteName: "InboxCollapsed-\(UUID().uuidString)"))
        let model = InboxScreenModel(loader: DemoInboxLoader(), defaults: defaults)
        model.setExpanded("involved", false)
        #expect(!InboxScreenModel(loader: DemoInboxLoader(), defaults: defaults).isExpanded("involved"))
        #expect(model.isExpanded("myTeams"))
    }

    @Test func buildsRepositorySearchQueries() {
        let query = GitHubRepositoryPullRequestLoader.searchQuery(
            repository: billing, text: "export", excludedAuthors: ["dg-renovate"])
        #expect(query == "is:pr is:open archived:false sort:updated-desc repo:acme/billing export -author:dg-renovate")
        let many = (1...60).map { "author-number-\($0)" }
        #expect(
            GitHubRepositoryPullRequestLoader.searchQuery(repository: billing, text: "", excludedAuthors: many).count
                <= InboxScope.maxQueryLength)
        #expect(GitHubRepositoryPullRequestLoader.countQuery(count: 2).contains("s1: search(query: $q1"))
        #expect(GitHubRepositoryPullRequestLoader.pageQuery(pageSize: 40).contains("after: $after"))
    }
}
