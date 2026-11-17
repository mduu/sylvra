import DesignSystem
import SwiftUI

/// Renders a comment body (pure): full Markdown like GitHub (headings, lists, tables, quotes, the HTML and
/// emoji bots use), with fenced code and review suggestions in their own blocks.
struct MarkdownBodyView: View {
    let markdown: String

    var body: some View {
        MarkdownView(
            text: markdown,
            codeBlock: { language, code in
                AnyView(CodeBlockView(code: code, isSuggestion: language == "suggestion"))
            })
    }

    /// Inline Markdown only (one-line previews).
    static func attributed(_ text: String) -> AttributedString {
        MarkdownView.inlineMarkdown(text)
    }
}

/// A fenced code block; suggestions are labelled and tinted like an added line.
private struct CodeBlockView: View {
    let code: String
    let isSuggestion: Bool

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            if isSuggestion {
                Label("Suggested change", systemImage: "pencil.line")
                    .font(.caption.weight(.medium))
                    .foregroundStyle(.secondary)
                    .padding(.horizontal, 8)
                    .padding(.vertical, 4)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(.quaternary.opacity(0.5))
            }
            Text(code.isEmpty ? " " : code)
                .font(.system(size: 12, design: .monospaced))
                .textSelection(.enabled)
                .padding(8)
                .frame(maxWidth: .infinity, alignment: .leading)
                .background(isSuggestion ? Color.green.opacity(0.12) : Color.secondary.opacity(0.08))
        }
        .clipShape(RoundedRectangle(cornerRadius: 6))
        .overlay(RoundedRectangle(cornerRadius: 6).strokeBorder(.separator))
    }
}

#Preview {
    MarkdownBodyView(
        markdown: "### Coverage\n| File | Δ |\n|---|---|\n| `Invoice.swift` | :white_check_mark: +2% |\n\n"
            + "Making it **String**-backed lets the menu list `ExportFormat`:\n\n"
            + SuggestionBlock.make(code: "enum ExportFormat: String, CaseIterable {")
    )
    .padding()
    .frame(width: 420)
}
