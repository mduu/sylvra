import Foundation
import SylvraCore

/// Demo / screenshot stand-in for the AI comment rewriter (no agent call).
nonisolated enum DemoCommentRewriter {
    static func rewrite(_ text: String, language: String, style: CommentRewriteStyle) async throws -> String {
        try await Task.sleep(for: .milliseconds(600))
        let suggestion = text.range(of: "```suggestion").map { String(text[$0.lowerBound...]) } ?? ""
        let german = language == "German"
        let prose =
            switch style {
            case .shorten:
                german ? "Erst summieren, dann einmal runden?" : "Sum first, then round once?"
            case .improve, .translate:
                german
                    ? "Pro Position gerundet weicht das Total um ein paar Rappen ab – könnten wir erst am Schluss runden?"
                    : "Rounding per line drifts the total by a few cents – could we round once after summing?"
            }
        return suggestion.isEmpty ? prose : prose + "\n\n" + suggestion
    }
}
