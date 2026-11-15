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
                Rephrase the following GitHub code review comment factually and write it in \(language), as if I — \
                the reviewer — wrote it myself. Keep it short and to the point: at most two sentences unless the \
                content truly needs more, never longer than the original.
                """
            case .shorten:
                """
                Make the following GitHub code review comment as short and crisp as possible, in \(language), in my \
                voice as the reviewer: ideally one sentence, at most two. Keep the point, drop filler, hedging and \
                repetition.
                """
            case .translate:
                """
                Translate the following GitHub code review comment into \(language). Keep wording, tone and length; \
                leave code, identifiers and Markdown untouched.
                """
            }
        return """
            \(task)
            Stay factual and neutral: name the observation, its concrete effect and, if there is one, the \
            suggested change. No judgment of the author, no loaded or emotional words, no sarcasm, no \
            exaggeration or absolutes ("always", "obviously", "just"), no exclamation marks. Polite but not chatty; \
            a question or a suggestion is fine where it is genuinely open.
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
