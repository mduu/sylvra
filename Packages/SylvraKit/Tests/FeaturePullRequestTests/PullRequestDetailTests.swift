import Foundation
import Platform
import SylvraCore
import Testing

@testable import FeaturePullRequest

struct PullRequestDetailMappingTests {
    static let json = """
        {"repository": {"pullRequest": {
          "number": 5, "title": "Add export", "url": "https://github.com/o/r/pull/5", "isDraft": false,
          "createdAt": "2026-11-01T10:00:00Z", "updatedAt": "2026-11-02T10:00:00Z",
          "additions": 20, "deletions": 4, "changedFiles": 3,
          "headRefName": "feat", "baseRefName": "main", "headRefOid": "aaaaaaaaaa", "baseRefOid": "bbbbbbbbbb",
          "reviewDecision": "REVIEW_REQUIRED", "mergeable": "MERGEABLE", "mergeStateStatus": "BLOCKED",
          "state": "OPEN", "body": "Hello **world**",
          "repository": {"name": "r", "owner": {"login": "o"}},
          "headRepositoryOwner": {"login": "o"},
          "author": {"login": "ann", "avatarUrl": null, "name": "Ann Lee"},
          "labels": {"nodes": [{"name": "bug", "color": "ff0000"}]},
          "assignees": {"nodes": []},
          "milestone": null,
          "closingIssuesReferences": {"nodes": [{"number": 1, "title": "Issue", "url": null}]},
          "reviewRequests": {"nodes": [
            {"requestedReviewer": {"__typename": "Team", "name": "Core", "slug": "core"}},
            {"requestedReviewer": {"__typename": "User", "login": "bob", "avatarUrl": null, "name": "Bob"}}]},
          "comments": {"nodes": [
            {"author": {"login": "bob", "avatarUrl": null, "name": "Bob"}, "body": "cc @mduu for the export",
             "createdAt": "2026-11-02T08:00:00Z", "url": "https://github.com/o/r/pull/5#issuecomment-1"},
            {"author": {"login": "mduu", "avatarUrl": null, "name": "Marc"}, "body": "Looks good, @bob",
             "createdAt": "2026-11-02T08:30:00Z", "url": null}]},
          "reviews": {"nodes": [{"author": {"login": "cid", "avatarUrl": null, "name": "Cid"}, "body": "",
            "submittedAt": "2026-11-02T09:00:00Z", "url": null}]},
          "reviewThreads": {"nodes": [{"path": "Sources/Export.swift", "line": 12, "comments": {"nodes": [
            {"author": {"login": "cid", "avatarUrl": null, "name": "Cid"}, "body": "@mduu is this right?",
             "createdAt": "2026-11-02T09:05:00Z", "url": null}]}}]},
          "latestReviews": {"nodes": [{"state": "APPROVED", "submittedAt": "2026-11-02T09:00:00Z",
            "author": {"login": "cid", "avatarUrl": null, "name": "Cid"}}]},
          "commits": {"totalCount": 1, "nodes": [{"commit": {
            "oid": "1234567890abcdef", "abbreviatedOid": "1234567", "messageHeadline": "Add export",
            "messageBody": "Body", "authoredDate": "2026-11-01T11:00:00Z", "url": null,
            "signature": {"isValid": true},
            "author": {"name": "Ann", "user": {"login": "ann", "avatarUrl": null, "name": "Ann Lee"}},
            "statusCheckRollup": {"state": "FAILURE"}}}]},
          "checks": {"nodes": [{"commit": {"statusCheckRollup": {"state": "FAILURE", "contexts": {"nodes": [
            {"__typename": "CheckRun", "name": "lint", "status": "COMPLETED", "conclusion": "SUCCESS",
             "startedAt": "2026-11-01T11:00:00Z", "completedAt": "2026-11-01T11:00:40Z", "detailsUrl": null},
            {"__typename": "CheckRun", "name": "build", "status": "COMPLETED", "conclusion": "FAILURE",
             "startedAt": null, "completedAt": null, "detailsUrl": "https://example.com/run"},
            {"__typename": "StatusContext", "context": "ci/legacy", "state": "PENDING",
             "targetUrl": null, "createdAt": "2026-11-01T11:00:00Z"}]}}}}]}
        }}}
        """

    private func detail() throws -> PullRequestDetail {
        let response = try GitHubJSON.decoder.decode(DetailResponse.self, from: Data(Self.json.utf8))
        return try #require(response.repository?.pullRequest).detail
    }

    @Test func findsMentionsOfTheViewer() throws {
        let response = try GitHubJSON.decoder.decode(DetailResponse.self, from: Data(Self.json.utf8))
        let involvement = try #require(response.repository?.pullRequest).involvement(of: "mduu")
        #expect(involvement.mentions.map(\.place) == [.codeComment(path: "Sources/Export.swift", line: 12), .comment])
        #expect(involvement.mentions.last?.excerpt == "cc @mduu for the export")
        #expect(involvement.ownCommentCount == 1)
        #expect(try #require(response.repository?.pullRequest).involvement(of: "zed").isEmpty)
    }

    /// The Comments tab: general comments without a code jump, threads with path and line, empty reviews skipped.
    @Test func collectsAllCommentsWithTheirPlace() throws {
        let response = try GitHubJSON.decoder.decode(DetailResponse.self, from: Data(Self.json.utf8))
        let items = try #require(response.repository?.pullRequest).discussion
        #expect(items.count == 3)
        #expect(items.filter { $0.codeLocation == nil }.count == 2)
        let thread = try #require(items.first { $0.codeLocation != nil })
        #expect(thread.codeLocation?.path == "Sources/Export.swift")
        #expect(thread.codeLocation?.line == 12)
        #expect(!thread.isResolved)

        let conversation = DiscussionFilter.conversation.apply(items)
        #expect(conversation.count == 2)
        #expect(conversation == conversation.sorted { $0.date < $1.date })
        #expect(DiscussionFilter.code.apply(items).count == 1)
        #expect(DiscussionFilter.open.apply(items).count == 1)
        var detail = try detail()
        detail.discussion = items
        #expect(detail.commentCount == 3)
    }

    @Test func mapsSummaryAndCommits() throws {
        let detail = try detail()
        #expect(detail.summary.id.description == "o/r#5")
        #expect(detail.summary.checkState == .failure)
        #expect(detail.commits.first?.shortSHA == "1234567")
        #expect(detail.commits.first?.isVerified == true)
        #expect(detail.linkedIssues.map(\.number) == [1])
    }

    @Test func sortsFailingChecksFirstAndComputesDuration() throws {
        let detail = try detail()
        #expect(detail.checks.map(\.name) == ["build", "ci/legacy", "lint"])
        #expect(detail.checks.last?.duration == .seconds(40))
    }

    @Test func combinesReviewsAndRequests() throws {
        let reviewers = try detail().reviewers
        #expect(reviewers.map(\.name) == ["cid", "@o/core", "bob"])
        #expect(reviewers.map(\.status) == [.approved, .pending, .pending])
        #expect(reviewers[1].isTeam)
    }

    @Test func explainsWhyMergeIsBlocked() throws {
        let status = try detail().mergeStatus
        #expect(status.kind == .blocked)
        #expect(status.reasons.count == 2)
    }
}

struct MergeStatusTests {
    @Test func cleanIsReady() {
        let status = MergeStatus.derive(
            state: .open, mergeStateStatus: "CLEAN", reviewDecision: .approved, checks: [], isDraft: false)
        #expect(status.kind == .ready)
    }

    @Test func mergedWins() {
        let status = MergeStatus.derive(
            state: .merged, mergeStateStatus: "DIRTY", reviewDecision: .none, checks: [], isDraft: false)
        #expect(status.kind == .merged)
    }

    @Test func conflictsAreReported() {
        let status = MergeStatus.derive(
            state: .open, mergeStateStatus: "DIRTY", reviewDecision: .approved, checks: [], isDraft: false)
        #expect(status.kind == .conflicts)
    }
}

@MainActor
struct PullRequestScreenModelTests {
    @Test func loadsAndClearsSelection() async {
        let model = PullRequestScreenModel(loader: DemoPullRequestDetailLoader())
        await model.load(PullRequestID(owner: "acme", repository: "billing", number: 1234))
        #expect(model.detail?.summary.title == "Add invoice export")
        #expect(model.loadState == .loaded)
        await model.load(nil)
        #expect(model.detail == nil)
    }

    @Test func resolvesCodeThreadsFromTheCommentsTab() async throws {
        let model = PullRequestScreenModel(loader: DemoPullRequestDetailLoader())
        await model.load(PullRequestID(owner: "acme", repository: "billing", number: 1234))
        var accepts = true
        model.resolveThread = { _, _ in accepts }
        let thread = try #require(model.detail?.discussion.first { $0.id == "t1" })
        #expect(!thread.isResolved)
        await model.toggleResolved(thread)
        #expect(model.detail?.discussion.first { $0.id == "t1" }?.isResolved == true)

        // GitHub refuses: the thread shows as resolved again.
        accepts = false
        let resolved = try #require(model.detail?.discussion.first { $0.id == "t1" })
        await model.toggleResolved(resolved)
        #expect(model.detail?.discussion.first { $0.id == "t1" }?.isResolved == true)

        // Reopened in the diff: the tab follows.
        model.markResolved("t1", false)
        #expect(model.detail?.discussion.first { $0.id == "t1" }?.isResolved == false)
    }
}
