import Foundation
import SylvraCore

/// AI writing help for review comments (see specs/projectidea.md §6, "comment tone helper"): better wording,
/// shorter, or translation — always short and in the reviewer's voice. Suggestion blocks stay verbatim.
public struct CommentRewriter: Sendable {
    private let provider: any AgentProvider
    private let model: String

    public init(provider: any AgentProvider, model: String = "sonnet") {
        self.provider = provider
        self.model = model
    }

    public func rewrite(_ text: String, language: String, style: CommentRewriteStyle = .improve) async throws
        -> String
    {
        let reply = try await provider.chat(
            ChatRequest(
                message: Self.prompt(for: text, language: language, style: style), sessionID: nil, model: model,
                language: language, workingDirectory: nil))
        let result = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Never lose a suggestion: fall back to the original if the agent dropped one.
        return SuggestionGuard.keepsSuggestions(original: text, rewritten: result) ? result : text
    }

    static func prompt(for text: String, language: String, style: CommentRewriteStyle) -> String {
        let task =
            switch style {
            case .improve:
                """
                Improve the wording of the following GitHub code review comment and write it in \(language), as if \
                I — the reviewer — wrote it myself. Keep it short and to the point: at most two sentences unless the \
                content truly needs more, never longer than the original. Personal and friendly; collaborative \
                rather than judgmental (prefer a question or a suggestion over a verdict); first person.
                """
            case .shorten:
                """
                Make the following GitHub code review comment as short and crisp as possible, in \(language), in my \
                voice as the reviewer: ideally one sentence, at most two. Keep the point and a friendly tone, drop \
                filler, hedging and repetition.
                """
            case .translate:
                """
                Translate the following GitHub code review comment into \(language). Keep wording, tone and length; \
                leave code, identifiers and Markdown untouched.
                """
            }
        return """
            \(task)
            No greeting, no sign-off, no filler phrases, no mention of AI. Keep Markdown and inline code.
            Keep every ```suggestion block exactly as it is, character for character.
            Reply with the comment text only.

            ---
            \(text)
            """
    }
}

/// Checks that rewriting kept all ```suggestion blocks unchanged.
enum SuggestionGuard {
    static func keepsSuggestions(original: String, rewritten: String) -> Bool {
        blocks(in: original).allSatisfy { rewritten.contains($0) }
    }

    static func blocks(in text: String) -> [String] {
        text.matches(of: /```suggestion\n[\s\S]*?```/).map { String($0.output) }
    }
}
