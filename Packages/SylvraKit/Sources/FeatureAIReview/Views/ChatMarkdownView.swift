import DesignSystem
import SwiftUI

/// An AI chat answer with block Markdown (pure). `inline` renders a block's text (bold, code spans,
/// links, clickable code references).
struct ChatMarkdownView: View {
    let text: String
    let inline: (String) -> AttributedString

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            ForEach(Array(ChatMarkdown.parse(text).enumerated()), id: \.offset) { _, block in
                blockView(block)
            }
        }
        .frame(maxWidth: .infinity, alignment: .leading)
    }

    @ViewBuilder private func blockView(_ block: ChatMarkdownBlock) -> some View {
        switch block {
        case .heading(let level, let text):
            Text(inline(text))
                .aiFont(level <= 2 ? .headline : .subheadline, weight: .semibold)
                .padding(.top, level <= 2 ? 4 : 2)
                .textSelection(.enabled)
        case .paragraph(let text):
            prose(text)
        case .list(let items):
            VStack(alignment: .leading, spacing: 4) {
                ForEach(Array(items.enumerated()), id: \.offset) { _, item in
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Text(item.marker)
                            .foregroundStyle(.secondary)
                            .monospacedDigit()
                        prose(item.text)
                    }
                    .padding(.leading, CGFloat(item.level) * 14)
                }
            }
        case .code(_, let code):
            monospaced(code)
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
            .aiFont(.callout)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
    }

    /// Code and tables keep their line breaks; long lines wrap (a sideways scroll area inside the chat's
    /// vertical scroll view would catch the mouse wheel).
    private func monospaced(_ text: String) -> some View {
        Text(text.isEmpty ? " " : text)
            .aiFont(.caption, design: .monospaced)
            .textSelection(.enabled)
            .fixedSize(horizontal: false, vertical: true)
            .padding(8)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(Color.secondary.opacity(0.08), in: RoundedRectangle(cornerRadius: 6))
    }
}

#Preview {
    ScrollView {
        ChatMarkdownView(
            text: """
                ## Summary
                The export rounds **each line** before summing (`InvoiceService.swift:9`).

                - Rounding per line can drift from the total
                - Totals differ by up to 1 cent
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
                """,
            inline: { (try? AttributedString(markdown: $0)) ?? AttributedString($0) }
        )
        .padding()
    }
    .frame(width: 340, height: 520)
}
