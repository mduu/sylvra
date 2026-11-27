import Testing

@testable import FeatureAIReview

@Suite struct ChatHandoffTests {
    @Test func carriesTheWholeChatAndWaits() {
        let messages = [
            AIChatModel.Message(role: .user, text: "Why did prod fail?"),
            AIChatModel.Message(role: .assistant, text: "The migration timed out."),
        ]
        let prompt = AIReviewClipboard.chatHandoff(messages, pullRequest: "acme/billing#812")
        #expect(prompt.contains("Why did prod fail?"))
        #expect(prompt.contains("The migration timed out."))
        #expect(prompt.contains("acme/billing#812"))
        #expect(prompt.contains("Wait for my instructions"))
    }
}
