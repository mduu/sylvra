import Foundation
import Platform
import SylvraCore
import Testing

@testable import FeatureReview

struct SuggestionBlockTests {
    @Test func buildsSuggestionBlock() {
        #expect(SuggestionBlock.make(code: "let a = 1\nlet b = 2") == "```suggestion\nlet a = 1\nlet b = 2\n```")
    }

    @Test func insertsIntoEmptyBody() {
        #expect(SuggestionBlock.insert(code: "x", into: "  \n") == "```suggestion\nx\n```\n")
    }

    @Test func appendsAfterExistingTextWithBlankLine() {
        #expect(SuggestionBlock.insert(code: "x", into: "Nit:\n") == "Nit:\n\n```suggestion\nx\n```\n")
    }

    @Test func replacementCodeBecomesSuggestion() {
        let body = SuggestionBlock.commentBody(
            rationale: "Use the quantity.", code: "    total += item.price * item.quantity",
            replacing: "    total += item.price")
        #expect(body == "Use the quantity.\n\n```suggestion\n    total += item.price * item.quantity\n```")
    }

    /// Regression: proposed code that is no 1:1 replacement became a suggestion GitHub offered to commit.
    @Test func otherCodeStaysAPlainCodeBlock() {
        let original = "    let total = items.reduce(0) { $0 + $1.price }"
        let sketch = "func testTotalIncludesQuantity() {\n    // ...\n}"
        #expect(
            SuggestionBlock.commentBody(rationale: "Add a test.", code: sketch, replacing: original)
                == "Add a test.\n\n```\n\(sketch)\n```")
        let prose = "Consider extracting this into a separate pricing service"
        #expect(!SuggestionBlock.isReplacement(prose, for: original))
        #expect(!SuggestionBlock.isReplacement("let total = 0", for: ""))
    }

    @Test func rationaleOnlyWithoutCode() {
        #expect(SuggestionBlock.commentBody(rationale: "Why?", code: nil, replacing: "x") == "Why?")
    }
}
