import DesignSystem
import SwiftUI

/// Renders a comment body: prose with inline Markdown, fenced code, and suggestions (pure).
struct MarkdownBodyView: View {
    let markdown: String

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlock.parse(markdown).enumerated()), id: \.offset) { _, block in
                switch block {
                case .text(let text):
                    Text(Self.attributed(text))
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                case .code(let language, let code):
                    CodeBlockView(code: code, isSuggestion: language == "suggestion")
                }
            }
        }
        .font(.callout)
    }

    static func attributed(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
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
        markdown: "Making it **String**-backed lets the menu list `ExportFormat`:\n\n"
            + SuggestionBlock.make(code: "enum ExportFormat: String, CaseIterable {")
    )
    .padding()
    .frame(width: 420)
}
