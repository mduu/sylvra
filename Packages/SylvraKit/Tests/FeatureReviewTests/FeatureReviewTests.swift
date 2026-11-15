import Foundation
import Platform
import SylvraCore
import Testing

@testable import FeatureReview

struct SuggestionBlockTests {
    @Test func buildsSuggestionBlock() {
        #expect(SuggestionBlock.make(code: "let a = 1\nlet b = 2") == "```suggestion\nlet a = 1\nlet b = 2\n```")
    }

    @Test func insertsIntoEmptyBody() {
        #expect(SuggestionBlock.insert(code: "x", into: "  \n") == "```suggestion\nx\n```\n")
    }

    @Test func appendsAfterExistingTextWithBlankLine() {
        #expect(SuggestionBlock.insert(code: "x", into: "Nit:\n") == "Nit:\n\n```suggestion\nx\n```\n")
    }
}

struct MarkdownBlockTests {
    @Test func splitsProseAndFencedCode() {
        let blocks = MarkdownBlock.parse("Why not:\r\n\r\n```suggestion\r\nlet a = 1\r\n```\r\nThanks")
        #expect(
            blocks == [.text("Why not:"), .code(language: "suggestion", code: "let a = 1"), .text("Thanks")])
    }

    @Test func keepsUnterminatedFence() {
        #expect(MarkdownBlock.parse("```swift\nfoo()") == [.code(language: "swift", code: "foo()")])
    }

    @Test func plainText() {
        #expect(MarkdownBlock.parse("**bold** text") == [.text("**bold** text")])
    }
}

struct GitHubReviewMappingTests {
    // swiftlint:disable line_length
    static let json = """
        {"repository":{"pullRequest":{"id":"PR_1",
          "reviews":{"nodes":[{"id":"PRR_other","viewerDidAuthor":false},{"id":"PRR_mine","viewerDidAuthor":true}]},
          "reviewThreads":{"nodes":[
            {"id":"T1","isResolved":false,"isOutdated":false,"path":"a.swift","line":12,"startLine":10,"originalLine":12,"originalStartLine":10,"diffSide":"RIGHT","viewerCanReply":true,"viewerCanResolve":true,"viewerCanUnresolve":false,
             "comments":{"nodes":[
               {"id":"C1","body":"Line one\\r\\nLine two","createdAt":"2026-07-13T13:44:14Z","url":"https://github.com/o/r/pull/1#discussion_r1","state":"SUBMITTED","viewerCanUpdate":false,"viewerCanDelete":false,"author":{"login":"octo","avatarUrl":"https://a/1","name":"Octo Cat"}},
               {"id":"C2","body":"Mine","createdAt":"2026-07-13T14:00:00Z","url":null,"state":"PENDING","viewerCanUpdate":true,"viewerCanDelete":true,"author":null}
             ]}},
            {"id":"T2","isResolved":true,"isOutdated":true,"path":"b.swift","line":null,"startLine":null,"originalLine":39,"originalStartLine":37,"diffSide":"LEFT","viewerCanReply":true,"viewerCanResolve":false,"viewerCanUnresolve":true,
             "comments":{"nodes":[]}},
            {"id":"T3","isResolved":false,"isOutdated":false,"path":"c.swift","line":null,"startLine":null,"originalLine":null,"originalStartLine":null,"diffSide":"RIGHT","viewerCanReply":true,"viewerCanResolve":true,"viewerCanUnresolve":false,
             "comments":{"nodes":[]}}
          ]}}}}
        """
    // swiftlint:enable line_length

    private func snapshot() throws -> ReviewSnapshot {
        let response = try GitHubJSON.decoder.decode(ReviewResponse.self, from: Data(Self.json.utf8))
        return try #require(response.repository?.pullRequest).snapshot
    }

    @Test func mapsThreadsAndPendingReview() throws {
        let snapshot = try snapshot()
        #expect(snapshot.pullRequestNodeID == "PR_1")
        #expect(snapshot.pendingReviewID == "PRR_mine")
        // File-level thread without any line is skipped.
        #expect(snapshot.threads.map(\.id) == ["T1", "T2"])
    }

    @Test func mapsLocationsAndComments() throws {
        let thread = try #require(try snapshot().threads.first)
        #expect(thread.location == CodeLocation(path: "a.swift", line: 12, side: .right, startLine: 10))
        #expect(thread.viewerCanResolve)
        let first = try #require(thread.comments.first)
        #expect(first.body == "Line one\nLine two")
        #expect(first.author == UserRef(login: "octo", name: "Octo Cat", avatarURL: URL(string: "https://a/1")))
        #expect(!first.isPending)
        let mine = try #require(thread.comments.last)
        #expect(mine.isPending && mine.viewerCanUpdate)
        #expect(mine.author.login == "ghost")
    }

    @Test func outdatedThreadsFallBackToOriginalLines() throws {
        let thread = try snapshot().threads[1]
        #expect(thread.location == CodeLocation(path: "b.swift", line: 39, side: .left, startLine: 37))
        #expect(thread.isOutdated && thread.isCollapsedByDefault)
        #expect(thread.viewerCanResolve)  // resolved → viewerCanUnresolve
    }

    @Test func locationVariablesOmitStartForSingleLines() {
        let single = GitHubReviewService.locationVariables(CodeLocation(path: "a", line: 3, side: .left))
        #expect(single["startLine"] == .null && single["startSide"] == .null && single["side"] == .string("LEFT"))
        let range = GitHubReviewService.locationVariables(CodeLocation(path: "a", line: 5, side: .right, startLine: 2))
        #expect(range["startLine"] == .int(2) && range["startSide"] == .string("RIGHT"))
    }
}

@MainActor
struct ReviewScreenModelTests {
    private let id = PullRequestID(owner: "acme", repository: "billing", number: 1234)
    private let location = CodeLocation(path: "Sources/Billing/InvoiceService.swift", line: 13, side: .right)

    private func loadedModel(_ snapshot: ReviewSnapshot = DemoReviewService.sample()) async -> ReviewScreenModel {
        let model = ReviewScreenModel(service: DemoReviewService(snapshot: snapshot))
        await model.load(id)
        return model
    }

    @Test func loadsThreadsByLine() async {
        let model = await loadedModel()
        #expect(model.loadState == .loaded)
        #expect(model.threads(at: CodeLocation(path: location.path, line: 9, side: .right)).count == 1)
        #expect(model.threads(at: CodeLocation(path: location.path, line: 9, side: .left)).isEmpty)
        #expect(model.pendingCount == 1)
    }

    @Test func resolvedThreadsStartCollapsedAndToggle() async throws {
        let model = await loadedModel()
        let resolved = try #require(model.threads.first { $0.isResolved })
        let open = try #require(model.threads.first { !$0.isResolved })
        #expect(model.isCollapsed(resolved))
        #expect(!model.isCollapsed(open))
        model.toggleCollapsed(resolved)
        #expect(!model.isCollapsed(resolved))
    }

    @Test func addingToReviewIncreasesPendingCount() async {
        let model = await loadedModel()
        model.startComment(at: location, lineText: "    func export() {")
        #expect(model.isDraftAnchored(at: location))
        model.draft?.body = "Nit"
        model.insertSuggestion()
        #expect(model.draft?.body == "Nit\n\n```suggestion\n    func export() {\n```\n")
        await model.addDraftToReview()
        #expect(model.draft == nil)
        #expect(model.pendingCount == 2)
        #expect(model.threads(at: location).first?.comments.first?.isPending == true)
    }

    @Test func addingToReviewStartsPendingReviewWhenMissing() async {
        var snapshot = DemoReviewService.sample()
        snapshot.pendingReviewID = nil
        snapshot.threads.removeLast()
        let model = await loadedModel(snapshot)
        #expect(!model.hasPendingReview)
        model.startComment(at: location, lineText: "")
        model.draft?.body = "Hello"
        await model.addDraftToReview()
        #expect(model.hasPendingReview)
        #expect(model.pendingCount == 1)
    }

    @Test func commentNowIsOnlyAllowedWithoutPendingReview() async {
        let model = await loadedModel()
        model.startComment(at: location, lineText: "")
        model.draft?.body = "Hello"
        await model.postDraftNow()
        #expect(model.draft != nil)  // blocked: pending review exists

        var snapshot = DemoReviewService.sample()
        snapshot.pendingReviewID = nil
        let fresh = await loadedModel(snapshot)
        fresh.startComment(at: location, lineText: "")
        fresh.draft?.body = "Hello"
        await fresh.postDraftNow()
        #expect(fresh.draft == nil)
        #expect(fresh.threads(at: location).first?.comments.first?.isPending == false)
    }

    @Test func startingOnOverlappingRangeKeepsText() async {
        let model = await loadedModel()
        model.startComment(at: location, lineText: "a")
        model.draft?.body = "Keep me"
        model.startComment(
            at: CodeLocation(path: location.path, line: 15, side: .right, startLine: 13), lineText: "a\nb\nc")
        #expect(model.draft?.body == "Keep me")
        #expect(model.draft?.location.startLine == 13)
        model.startComment(at: CodeLocation(path: location.path, line: 2, side: .right), lineText: "")
        #expect(model.draft?.body == "")
    }

    @Test func repliesAndResolves() async throws {
        let model = await loadedModel()
        let thread = try #require(model.threads.first { !$0.isResolved })
        model.replyDrafts[thread.id] = "Sounds good"
        await model.reply(to: thread)
        let updated = try #require(model.threads.first { $0.id == thread.id })
        #expect(updated.comments.last?.body == "Sounds good")
        #expect(updated.comments.last?.isPending == true)  // pending review exists
        #expect(model.replyDrafts[thread.id] == nil)

        await model.setResolved(true, thread: updated)
        #expect(model.threads.first { $0.id == thread.id }?.isResolved == true)
        #expect(model.isCollapsed(try #require(model.threads.first { $0.id == thread.id })))
    }

    @Test func editsAndDeletesOwnComment() async throws {
        let model = await loadedModel()
        let mine = try #require(model.pendingComments.first?.comment)
        model.beginEditing(mine)
        model.editDrafts[mine.id] = "Edited"
        await model.saveEdit(of: mine)
        #expect(model.pendingComments.first?.comment.body == "Edited")
        #expect(model.editDrafts.isEmpty)

        await model.delete(mine)
        #expect(model.pendingCount == 0)
        #expect(model.threads.count == 2)  // the now empty thread is gone
    }

    @Test func submitClearsPendingReview() async {
        let model = await loadedModel()
        model.isSubmitSheetPresented = true
        model.submitEvent = .approve
        model.submitBody = "LGTM"
        await model.submitReview()
        #expect(!model.hasPendingReview)
        #expect(model.pendingCount == 0)
        #expect(!model.isSubmitSheetPresented)
        #expect(model.submitBody.isEmpty && model.submitEvent == .comment)
    }

    @Test func requestChangesNeedsSummary() async {
        let model = await loadedModel()
        model.submitEvent = .requestChanges
        await model.submitReview()
        #expect(model.errorMessage != nil)
        #expect(model.hasPendingReview)
    }

    @Test func failedResolveRollsBack() async throws {
        let model = ReviewScreenModel(service: FailingResolveService())
        await model.load(id)
        let thread = try #require(model.threads.first { !$0.isResolved })
        await model.setResolved(true, thread: thread)
        #expect(model.threads.first { $0.id == thread.id }?.isResolved == false)
        #expect(model.errorMessage != nil)
    }
}

/// Demo data, but resolving fails.
private struct FailingResolveService: ReviewService {
    private let demo = DemoReviewService()

    func loadReview(for id: PullRequestID) async throws -> ReviewSnapshot { try await demo.loadReview(for: id) }
    func startPendingReview(pullRequestNodeID: String) async throws -> String { "r" }
    func addThread(reviewID: String, location: CodeLocation, body: String) async throws -> ReviewThread {
        throw GitHubError.notAuthenticated
    }
    func postComment(pullRequestNodeID: String, location: CodeLocation, body: String) async throws {}
    func reply(threadID: String, reviewID: String?, body: String) async throws -> ReviewComment {
        throw GitHubError.notAuthenticated
    }
    func setResolved(_ resolved: Bool, threadID: String) async throws { throw GitHubError.notAuthenticated }
    func updateComment(id: String, body: String) async throws -> ReviewComment { throw GitHubError.notAuthenticated }
    func deleteComment(id: String) async throws {}
    func submitReview(pullRequestNodeID: String, reviewID: String?, event: ReviewEvent, body: String) async throws {}
}

@MainActor
struct CommentLanguageTests {
    private let id = PullRequestID(owner: "acme", repository: "lang-\(UUID().uuidString)", number: 1)
    private let location = CodeLocation(path: "A.swift", line: 3, side: .right)

    @Test func rewritesDraftInChosenLanguageAndRemembersItPerRepository() async {
        let model = ReviewScreenModel(service: DemoReviewService(snapshot: DemoReviewService.sample()))
        await model.load(id)
        model.rewriter = { text, language in "[\(language)] \(text)" }
        model.startComment(at: location, lineText: "x")
        model.draft?.body = "Round once."

        await model.rewriteDraft()
        #expect(model.draft?.body == "[English] Round once.")

        model.draftLanguage = "German"
        #expect(model.draftLanguage == "German")
        // The language switch triggers a rewrite of the current draft.
        try? await Task.sleep(for: .milliseconds(50))
        #expect(model.draft?.body == "[German] [English] Round once.")
    }
}
