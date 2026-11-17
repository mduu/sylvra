import Testing

@testable import FeatureAIReview

struct ChatMarkdownTests {
    @Test func splitsAnAnswerIntoBlocks() {
        let blocks = ChatMarkdown.parse(
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
                    ChatListItem(marker: "•", level: 0, text: "one"),
                    ChatListItem(marker: "•", level: 0, text: "two\ncontinued"),
                    ChatListItem(marker: "•", level: 1, text: "nested"),
                    ChatListItem(marker: "3.", level: 0, text: "third"),
                ]),
                .quote("quoted"),
                .rule,
                .table("a | b\n--+--"),
                .code(language: "swift", code: "let x = 1\n\nlet y = 2"),
            ])
    }

    @Test func keepsAnUnclosedFenceWhileStreaming() {
        #expect(ChatMarkdown.parse("Look:\n```\nfoo") == [.paragraph("Look:"), .code(language: nil, code: "foo")])
    }

    @Test func treatsHashWithoutSpaceAndPlainTextAsParagraphs() {
        #expect(ChatMarkdown.parse("#123 is the PR") == [.paragraph("#123 is the PR")])
        #expect(ChatMarkdown.parse("2026 was a year") == [.paragraph("2026 was a year")])
    }

    @Test func alignsTableColumns() {
        #expect(
            ChatMarkdown.alignTable(["| Case | Result |", "|---|:---:|", "| 3 lines | ok |"])
                == "Case    | Result\n--------+-------\n3 lines | ok    ")
    }
}
