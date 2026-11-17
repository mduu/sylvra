import SwiftUI

/// Block Markdown (pure): AI chat answers and pull request descriptions. `inline` renders a block's
/// text (bold, code spans, links; the chat adds clickable code references).
public struct MarkdownView: View {
    /// `.ai` scales with the AI text size setting; `.standard` uses the system text styles.
    public enum Style: Sendable { case standard, ai }

    let text: String
    let style: Style
    let inline: (String) -> AttributedString
    let codeBlock: ((_ language: String?, _ code: String) -> AnyView?)?

    /// - Parameter codeBlock: renders a fenced code block itself (e.g. review suggestions); `nil` from it
    ///   falls back to the default monospaced block.
    public init(
        text: String, style: Style = .standard,
        inline: @escaping (String) -> AttributedString = MarkdownView.inlineMarkdown,
        codeBlock: ((_ language: String?, _ code: String) -> AnyView?)? = nil
    ) {
        self.text = text
        self.style = style
        self.inline = inline
        self.codeBlock = codeBlock
    }

    /// Inline Markdown (bold, italics, code spans, links), keeping line breaks.
    public nonisolated static func inlineMarkdown(_ text: String) -> AttributedString {
        let options = AttributedString.MarkdownParsingOptions(interpretedSyntax: .inlineOnlyPreservingWhitespace)
        return (try? AttributedString(markdown: text, options: options)) ?? AttributedString(text)
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(MarkdownBlocks.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func blockView(_ block: MarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .markdownFont(style, level <= 2 ? .headline : .subheadline, weight: .semibold)
                .padding(.top, level <= 2 ? 4 : 2)
                .textSelection(.enabled)
        case .paragraph(let text):
            prose(text)
        case .list(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.marker)
                            .markdownFont(style, .callout)
                            .foregroundStyle(.secondary)
                            .monospacedDigit().frame(minWidth: 12, alignment: .leading)
                        prose(item.text)
                    }
                    .padding(.leading, CGFloat(item.level) * 14)
                }
            }
        case .code(let language, let code):
            if let custom = codeBlock?(language, code) {
                custom
            } else {
                monospaced(code)
            }
        case .table(let rows):
            monospaced(rows)
        case .quote(let text):
            prose(text)
                .foregroundStyle(.secondary)
                .padding(.leading, 10)
                .overlay(alignment: .leading) {
                    RoundedRectangle(cornerRadius: 1).fill(.separator).frame(width: 3)
                }
        case .rule:
            Divider()
        }
    }

    private func prose(_ text: String) -> some View {
        Text(inline(text))
            .markdownFont(style, .callout)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Code and tables keep their line breaks; long lines wrap (a sideways scroll area inside a
    /// vertical scroll view would catch the mouse wheel).
    private func monospaced(_ text: String) -> some View {
        Text(text.isEmpty ? " " : text)
            .markdownFont(style, .caption, design: .monospaced)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

extension View {
    @ViewBuilder fileprivate func markdownFont(
        _ style: MarkdownView.Style, _ textStyle: Font.TextStyle, weight: Font.Weight? = nil,
        design: Font.Design? = nil
    ) -> some View {
        switch style {
        case .ai: aiFont(textStyle, weight: weight, design: design)
        case .standard: font(.system(textStyle, design: design, weight: weight))
        }
    }
}

#Preview {
    ScrollView {
        MarkdownView(
            text: """
                ## Summary
                The export rounds **each line** before summing (`InvoiceService.swift:9`).
                <!-- template hint -->

                - [x] Tests added
                - [ ] Docs updated
                - Rounding per line can drift from the total
                  on large invoices
                1. Round once at the end
                2. Or document the rule

                > Accounting wants per-line rounding.

                ```swift
                let total = lines.map(\\.amount).reduce(0, +)
                ```

                | Case | Result |
                |------|--------|
                | 3 lines | ok |
                """
        )
        .padding()
    }
    .frame(width: 340, height: 560)
}
