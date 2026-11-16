import Foundation
import Observation
import SylvraCore
import Testing

@testable import FeatureReview

private final class Flag: @unchecked Sendable {
    var isSet = false
}

@MainActor
struct ThreadRefreshTests {
    private let id = PullRequestID(owner: "acme", repository: "billing", number: 1234)

    /// Reloading without changes must not touch the state (no re-render, no scroll jumps).
    @Test func refreshOnlyTouchesTheStateWhenThreadsChanged() async throws {
        let service = DemoReviewService()
        let model = ReviewScreenModel(service: service)
        await model.load(id)
        let flag = Flag()
        withObservationTracking {
            _ = model.snapshot
        } onChange: {
            flag.isSet = true
        }
        await model.refreshThreads()
        await model.load(id)
        #expect(!flag.isSet)

        let thread = try #require(model.threads.first)
        _ = try await service.reply(threadID: thread.id, reviewID: nil, body: "Done, thanks")
        await model.refreshThreads()
        #expect(flag.isSet)
        #expect(model.threads.first?.comments.last?.body == "Done, thanks")
    }

    @Test func asksTheAIWithTheWholeDiscussionAndTakesItsSuggestedReply() async throws {
        let model = ReviewScreenModel(service: DemoReviewService())
        await model.load(id)
        let thread = try #require(model.threads.first)
        let question = model.aiQuestion(about: thread)
        for comment in thread.comments { #expect(question.contains(comment.body)) }
        #expect(question.contains(ReviewScreenModel.suggestedReplyMarker))

        let answer = "The reply is right.\n\nSuggested reply: \"Thanks, makes sense!\""
        #expect(ReviewScreenModel.suggestedReply(in: answer) == "Thanks, makes sense!")
        #expect(ReviewScreenModel.suggestedReply(in: "  No marker here ") == "No marker here")

        model.setReplyDraft("Thanks!", for: thread.id)
        #expect(model.replyDrafts[thread.id] == "Thanks!")
    }
}
