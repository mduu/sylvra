import Foundation
import Testing

@testable import SylvraCore

struct PullRequestWebURLTests {
    private func summary(url: URL?) -> PullRequestSummary {
        PullRequestSummary(
            id: PullRequestID(owner: "acme", repository: "billing", number: 12), title: "T",
            author: UserRef(login: "ann"), url: url, createdAt: .now, updatedAt: .now, additions: 0, deletions: 0,
            headRefName: "feat", baseRefName: "main")
    }

    @Test func usesTheAPIURLAndDerivesTheRepository() {
        let pr = summary(url: URL(string: "https://git.example.com/acme/billing/pull/12"))
        #expect(pr.webURL?.absoluteString == "https://git.example.com/acme/billing/pull/12")
        #expect(pr.repositoryWebURL?.absoluteString == "https://git.example.com/acme/billing")
    }

    @Test func fallsBackToGitHub() {
        let pr = summary(url: nil)
        #expect(pr.webURL?.absoluteString == "https://github.com/acme/billing/pull/12")
        #expect(pr.repositoryWebURL?.absoluteString == "https://github.com/acme/billing")
    }
}
