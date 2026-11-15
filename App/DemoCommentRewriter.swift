import Foundation

/// Demo / screenshot stand-in for the AI comment rewriter (no agent call).
nonisolated enum DemoCommentRewriter {
    static func rewrite(_ text: String, language: String) async throws -> String {
        try await Task.sleep(for: .milliseconds(600))
        let suggestion = text.range(of: "```suggestion").map { String(text[$0.lowerBound...]) } ?? ""
        let prose =
            language == "German"
            ? "Wenn wir jede Position einzeln runden, weicht das Total bei vielen kleinen Positionen um ein paar Rappen ab. "
                + "Könnten wir erst am Schluss runden? So in etwa:"
            : "Rounding each line before summing can drift the total by a few cents on invoices with many small items. "
                + "Could we round once after summing instead? Something like:"
        return suggestion.isEmpty ? prose : prose + "\n\n" + suggestion
    }
}
