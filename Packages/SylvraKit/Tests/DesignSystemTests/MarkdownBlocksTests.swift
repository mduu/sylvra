import Testing

@testable import DesignSystem

struct MarkdownBlocksTests {
    @Test func splitsAnAnswerIntoBlocks() {
        let blocks = MarkdownBlocks.parse(
            """
            ## Summary
            Rounds **each line**.
            Second line.

            - one
            - two
              continued
              - nested
            3. third

            > quoted

            ---
            | a | b |
            |---|---|
            ```swift
            let x = 1

            let y = 2
            ```
            """)
        #expect(
            blocks == [
                .heading(level: 2, text: "Summary"),
                .paragraph("Rounds **each line**.\nSecond line."),
                .list([
                    MarkdownListItem(marker: "•", level: 0, text: "one"),
                    MarkdownListItem(marker: "•", level: 0, text: "two\ncontinued"),
                    MarkdownListItem(marker: "•", level: 1, text: "nested"),
                    MarkdownListItem(marker: "3.", level: 0, text: "third"),
                ]),
                .quote("quoted"),
                .rule,
                .table("a | b\n--+--"),
                .code(language: "swift", code: "let x = 1\n\nlet y = 2"),
            ])
    }

    @Test func keepsAnUnclosedFenceWhileStreaming() {
        #expect(MarkdownBlocks.parse("Look:\n```\nfoo") == [.paragraph("Look:"), .code(language: nil, code: "foo")])
    }

    @Test func treatsHashWithoutSpaceAndPlainTextAsParagraphs() {
        #expect(MarkdownBlocks.parse("#123 is the PR") == [.paragraph("#123 is the PR")])
        #expect(MarkdownBlocks.parse("2026 was a year") == [.paragraph("2026 was a year")])
    }

    @Test func alignsTableColumns() {
        #expect(
            MarkdownBlocks.alignTable(["| Case | Result |", "|---|:---:|", "| 3 lines | ok |"])
                == "Case    | Result\n--------+-------\n3 lines | ok    ")
    }

    @Test func readsGitHubPullRequestDescriptions() {
        let blocks = MarkdownBlocks.parse(
            """
            <!-- Describe your change -->
            ## What
            Adds CSV export.
            <!--
            multi-line template hint
            -->
            - [x] Tests added
            - [ ] Docs updated

            <details>
            <summary>Screenshots</summary>

            ![Export dialog](https://example.com/a.png)
            <img width="400" src="https://example.com/b.png">
            </details>
            """)
        #expect(
            blocks == [
                .heading(level: 2, text: "What"),
                .paragraph("Adds CSV export."),
                .list([
                    MarkdownListItem(marker: "☑", level: 0, text: "Tests added"),
                    MarkdownListItem(marker: "☐", level: 0, text: "Docs updated"),
                ]),
                .paragraph("**Screenshots**"),
                .paragraph("[🖼 Export dialog](https://example.com/a.png)\n[🖼 Image](https://example.com/b.png)"),
            ])
    }

    @Test func keepsHTMLAndImagesInsideCodeBlocks() {
        #expect(
            MarkdownBlocks.parse("```html\n<details>\n![x](y)\n```")
                == [.code(language: "html", code: "<details>\n![x](y)")])
    }
}
