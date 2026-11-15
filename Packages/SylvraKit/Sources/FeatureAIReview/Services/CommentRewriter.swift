import Foundation

/// Rewrites a review comment draft so it reads like the reviewer wrote it (see specs/projectidea.md §6,
/// "comment tone helper"). Suggestion blocks stay verbatim.
public struct CommentRewriter: Sendable {
    private let provider: any AgentProvider
    private let model: String

    public init(provider: any AgentProvider, model: String = "sonnet") {
        self.provider = provider
        self.model = model
    }

    public func rewrite(_ text: String, language: String) async throws -> String {
        let reply = try await provider.chat(
            ChatRequest(
                message: Self.prompt(for: text, language: language), sessionID: nil, model: model, language: language,
                workingDirectory: nil))
        let result = reply.text.trimmingCharacters(in: .whitespacesAndNewlines)
        // Never lose a suggestion: fall back to the original if the agent dropped one.
        return SuggestionGuard.keepsSuggestions(original: text, rewritten: result) ? result : text
    }

    static func prompt(for text: String, language: String) -> String {
        """
        Rewrite the following GitHub code review comment in \(language), as if I — the reviewer — wrote it myself.
        Personal, friendly and concise; collaborative rather than judgmental (prefer a question or a suggestion over
        a verdict); first person; no greeting, no sign-off, no mention of AI. Keep Markdown.
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
