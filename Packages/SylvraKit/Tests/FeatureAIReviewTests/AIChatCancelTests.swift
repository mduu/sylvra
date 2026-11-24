import Foundation
import SylvraCore
import Testing

@testable import FeatureAIReview

/// A question sent too early can be stopped; it goes back into the input.
@MainActor
struct AIChatCancelTests {
    let id = PullRequestID(owner: "acme", repository: "billing", number: 1234)

    @Test func stoppingPutsTheQuestionBackIntoTheInput() async {
        let chat = AIChatModel(
            provider: DemoAgentProvider(delay: .seconds(60)), settings: { _ in ReviewSettings() },
            prContext: { _ in "PR context" }, workspace: { _ in nil })
        chat.draft = "Was ändert sich"
        let sending = Task { await chat.send(for: id) }
        while !chat.isSending { await Task.yield() }
        #expect(chat.draft.isEmpty)
        #expect(chat.messages(for: id).map(\.role) == [.user])

        chat.cancel()
        await sending.value
        #expect(!chat.isSending)
        #expect(chat.messages(for: id).isEmpty)
        #expect(chat.draft == "Was ändert sich")
    }

    @Test func stoppingKeepsWhatTheReviewerTypedMeanwhile() async {
        let chat = AIChatModel(
            provider: DemoAgentProvider(delay: .seconds(60)), settings: { _ in ReviewSettings() },
            prContext: { _ in "PR context" }, workspace: { _ in nil })
        let sending = Task { await chat.send("Explain this change", for: id) }
        while !chat.isSending { await Task.yield() }
        chat.draft = "Neue Frage"
        chat.cancel()
        await sending.value
        #expect(chat.draft == "Neue Frage")
        #expect(chat.messages(for: id).isEmpty)
    }
}
