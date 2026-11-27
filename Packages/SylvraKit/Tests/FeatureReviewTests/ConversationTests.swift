import Foundation
import Platform
import SylvraCore
import Testing

@testable import FeatureReview

@MainActor
struct ConversationTests {
    let id = PullRequestID(owner: "acme", repository: "billing", number: 1234)

    @Test func loadsOldestFirstAndCountsOnlyEntriesWithText() async {
        let model = ConversationModel(service: DemoConversationService())
        await model.load(id)
        #expect(model.loadState == .loaded)
        #expect(model.entries == model.entries.sorted { $0.comment.createdAt < $1.comment.createdAt })
        #expect(model.conversation?.commentCount == 3)
        #expect(model.entries.contains { $0.isEvent })
    }

    @Test func postsANewCommentAndClearsTheDraft() async {
        let model = ConversationModel(service: DemoConversationService())
        await model.load(id)
        model.draft = "Checked the PDF totals."
        await model.post()
        #expect(model.entries.last?.comment.body == "Checked the PDF totals.")
        #expect(model.draft.isEmpty)
    }

    @Test func keepsDraftsPerPullRequest() async {
        let model = ConversationModel(service: DemoConversationService())
        await model.load(id)
        model.draft = "Half written"
        await model.load(PullRequestID(owner: "acme", repository: "billing", number: 1))
        #expect(model.draft.isEmpty)
        await model.load(id)
        #expect(model.draft == "Half written")
    }

    @Test func quoteReplyQuotesEveryLineAndRequestsFocus() async throws {
        let model = ConversationModel(service: DemoConversationService())
        await model.load(id)
        let entry = try #require(model.entries.first)
        model.quoteReply(to: entry)
        #expect(model.draft.hasPrefix("> Ready for review."))
        #expect(model.draft.hasSuffix("\n\n"))
        #expect(model.composerFocusRequest == 1)
        #expect(QuoteReply.draft(quoting: "a\n\nb", into: "Hi") == "Hi\n\n> a\n>\n> b\n\n")
    }

    @Test func editsAndDeletesOwnComments() async throws {
        let model = ConversationModel(service: DemoConversationService())
        await model.load(id)
        let own = try #require(model.entries.first { $0.canDelete })
        model.beginEditing(own)
        model.editDrafts[own.id] = "Updated"
        await model.saveEdit(of: own)
        #expect(model.entries.first { $0.id == own.id }?.comment.body == "Updated")
        #expect(model.editDrafts.isEmpty)
        await model.delete(own)
        #expect(!model.entries.contains { $0.id == own.id })
    }

    @Test func reviewsCannotBeDeleted() {
        let review = ConversationEntry(
            kind: .review(.commented),
            comment: ReviewComment(
                id: "r", author: UserRef(login: "a"), body: "x", createdAt: .now, viewerCanDelete: true))
        #expect(!review.canDelete)
    }

    @Test func rollsBackAFailedReaction() async throws {
        let model = ConversationModel(service: FailingConversationService())
        await model.load(id)
        let entry = try #require(model.entries.first)
        let before = entry.comment.reactions
        await model.toggleReaction(.heart, on: entry)
        #expect(model.entries.first?.comment.reactions == before)
        #expect(model.errorMessage != nil)
    }

    @Test func mapsGitHubCommentsAndReviews() throws {
        let json = """
            {"repository":{"pullRequest":{"id":"PR_1",
              "comments":{"nodes":[{"id":"IC_1","body":"Hi","createdAt":"2026-11-01T10:00:00Z","url":null,
                "viewerCanUpdate":true,"viewerCanDelete":true,"author":{"login":"lena","avatarUrl":null},
                "reactionGroups":[{"content":"HEART","viewerHasReacted":true,"reactors":{"totalCount":2}}]}]},
              "reviews":{"nodes":[
                {"id":"R_1","state":"APPROVED","body":"","createdAt":"2026-11-01T12:00:00Z","url":null,
                 "viewerCanUpdate":false,"viewerCanDelete":false,"author":{"login":"jonas","avatarUrl":null},
                 "reactionGroups":[]},
                {"id":"R_2","state":"COMMENTED","body":"","createdAt":"2026-11-01T11:00:00Z","url":null,
                 "viewerCanUpdate":false,"viewerCanDelete":false,"author":{"login":"jonas","avatarUrl":null},
                 "reactionGroups":[]}]}}}}
            """
        let response = try GitHubJSON.decoder.decode(ConversationResponse.self, from: Data(json.utf8))
        let conversation = try #require(response.repository?.pullRequest).conversation
        #expect(conversation.pullRequestNodeID == "PR_1")
        #expect(conversation.entries.map(\.id) == ["IC_1", "R_1"])
        #expect(conversation.entries.first?.comment.reactions.first?.count == 2)
        #expect(conversation.entries.last?.kind == .review(.approved))
        #expect(conversation.entries.last?.isEvent == true)
    }
}

@MainActor
struct ConversationWritingTests {
    let id = PullRequestID(owner: "acme", repository: "writing-tests-\(UUID().uuidString)", number: 1)

    @Test func rewritesTheNewCommentAndUndoes() async {
        let model = ConversationModel(service: DemoConversationService())
        model.rewriter = { text, language, style in "\(style.rawValue) \(language): \(text)" }
        await model.load(id)
        model.draft = "this is wrong"
        await model.rewriteDraft(.improve)
        #expect(model.draft == "improve English: this is wrong")
        #expect(!model.isRewriting)
        model.undoRewrite()
        #expect(model.draft == "this is wrong")
        #expect(model.textBeforeRewrite == nil)
    }

    @Test func switchingTheLanguageTranslates() async throws {
        let model = ConversationModel(service: DemoConversationService())
        model.rewriter = { text, language, _ in "[\(language)] \(text)" }
        await model.load(id)
        model.draft = "Danke"
        model.draftLanguage = "German"
        // The translation runs in a task of its own: wait for it (generously, CI runners are slow).
        for _ in 0..<300 where model.draft != "[German] Danke" { try await Task.sleep(for: .milliseconds(10)) }
        #expect(model.draft == "[German] Danke")
        UserDefaults.standard.removeObject(forKey: ReviewScreenModel.languageKey(id))
    }

    @Test func doesNothingWithoutARewriter() async {
        let model = ConversationModel(service: DemoConversationService())
        await model.load(id)
        model.draft = "text"
        await model.rewriteDraft()
        #expect(model.draft == "text")
    }
}

/// Loads the demo conversation; every write fails.
private struct FailingConversationService: ConversationService {
    struct Failure: Error {}

    func loadConversation(for id: PullRequestID) async throws -> Conversation { DemoConversationService.sample() }
    func addComment(pullRequestNodeID: String, body: String) async throws -> ConversationEntry { throw Failure() }
    func updateBody(of entry: ConversationEntry, to body: String) async throws -> String { throw Failure() }
    func deleteComment(id: String) async throws { throw Failure() }
    func setReaction(_ reaction: Reaction, added: Bool, subjectID: String) async throws { throw Failure() }
}
