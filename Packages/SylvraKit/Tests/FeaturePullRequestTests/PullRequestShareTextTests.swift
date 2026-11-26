import Foundation
import SylvraCore
import Testing

@testable import FeaturePullRequest

/// The link with title and a short description, for asking for a review in a chat.
struct PullRequestShareTextTests {
    private func detail(body: String) -> PullRequestDetail {
        var detail = DemoPullRequestDetailLoader.detail(for: .init(owner: "acme", repository: "billing", number: 1234))
        detail.body = body
        return detail
    }

    @Test func takesTheFirstTwoSentencesOfTheDescription() {
        let detail = detail(
            body: """
                <!-- What does this change and why? -->
                ## Summary
                Adds a **CSV export** for invoices, e.g. for the monthly closing. It streams rows instead of \
                loading them all. A third sentence nobody needs in a chat.

                ## Testing
                - [x] Unit tests
                """)
        #expect(
            PullRequestShareText.text(for: detail) == """
                Add invoice export (billing #1234)
                https://github.com/acme/billing/pull/1234/
                Adds a CSV export for invoices, e.g. for the monthly closing. It streams rows instead of loading them all.
                """)
    }

    @Test func prefersTheGivenSummary() {
        let text = PullRequestShareText.text(
            for: detail(body: "From the description."), summary: "From the AI review. Main risk: rounding. More.")
        #expect(text.hasSuffix("From the AI review. Main risk: rounding."))
    }

    @Test func withoutAnyTextItIsTitleAndLink() {
        let text = PullRequestShareText.text(for: detail(body: "<!-- template only -->\n## Summary\n"))
        #expect(text == "Add invoice export (billing #1234)\nhttps://github.com/acme/billing/pull/1234/")
    }

    @Test func longTextIsCutAndListsBecomeSentences() {
        let long = String(repeating: "word ", count: 100)
        #expect(PullRequestShareText.firstSentences(of: long, count: 2).count == PullRequestShareText.maxLength)
        #expect(
            PullRequestShareText.plain("- Fix `rounding`\n- [Link](https://x.y) text") == "Fix rounding. Link text.")
    }

    @Test func theHTMLVersionLinksTheTitle() {
        let html = PullRequestShareText.html(for: detail(body: "Fixes a < b."))
        #expect(
            html == "<a href=\"https://github.com/acme/billing/pull/1234/\">Add invoice export (billing #1234)</a>"
                + "<br>Fixes a &lt; b.")
    }
}
