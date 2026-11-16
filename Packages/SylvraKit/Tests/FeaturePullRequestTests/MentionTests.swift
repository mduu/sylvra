import Foundation
import Testing

@testable import FeaturePullRequest

struct MentionFinderTests {
    @Test func findsWholeWordMentionsCaseInsensitively() {
        #expect(MentionFinder.mentions("mduu", in: "cc @MDUU please"))
        #expect(MentionFinder.mentions("mduu", in: "@mduu: look"))
        #expect(!MentionFinder.mentions("mduu", in: "cc @mduu-bot please"))
        #expect(!MentionFinder.mentions("mduu", in: "mail mduu@example.com"))
        #expect(!MentionFinder.mentions("mduu", in: "no mention"))
    }

    @Test func ignoresCodeSpansAndQuotedReplies() {
        #expect(!MentionFinder.mentions("mduu", in: "run `notify @mduu` later"))
        #expect(!MentionFinder.mentions("mduu", in: "> @mduu wrote this\n\nThanks!"))
    }

    @Test func excerptIsTheMentioningParagraph() {
        let text = "First paragraph.\n\nSecond line mentions\n@mduu here.\n\nThird."
        #expect(MentionFinder.excerpt(mentioning: "mduu", in: text) == "Second line mentions @mduu here.")
        let long = "@mduu " + String(repeating: "word ", count: 100)
        #expect(MentionFinder.excerpt(mentioning: "mduu", in: long, limit: 50)?.count == 50)
    }
}
