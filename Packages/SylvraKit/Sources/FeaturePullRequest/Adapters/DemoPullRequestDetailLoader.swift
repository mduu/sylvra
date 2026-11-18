import Foundation
import SylvraCore

/// Fixture details for `--demo`, previews and screenshots.
public struct DemoPullRequestDetailLoader: PullRequestDetailLoading {
    public init() {}

    public func loadDetail(for id: PullRequestID) async throws -> PullRequestDetail {
        Self.detail(for: id)
    }

    public func loadCheckReport(nodeID: String) async throws -> CheckReport {
        CheckReport(
            title: "1 test failed, 41 passed",
            summary: """
                ## Test results
                **41 passed**, **1 failed**, 0 skipped in 4m 12s.

                ### Failed
                - `InvoiceServiceTests.totalRoundsPerLine()`
                """,
            text: """
                ```
                InvoiceServiceTests.swift:31: error: #expect(service.total(for: .sample) == 42.30)
                  -> 42.29 != 42.30
                ```
                """,
            annotations: [
                .init(
                    path: "Tests/BillingTests/InvoiceServiceTests.swift", line: 31, level: .failure,
                    title: "totalRoundsPerLine()", message: "Expectation failed: 42.29 != 42.30")
            ])
    }

    // swiftlint:disable:next function_body_length
    static func detail(for id: PullRequestID) -> PullRequestDetail {
        let lena = UserRef(login: "lkeller", name: "Lena Keller")
        let jonas = UserRef(login: "jmeier", name: "Jonas Meier")
        let marc = UserRef(login: "mduu", name: "Marc Dürst")
        let now = Date.now
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }

        let checks: [PullRequestDetail.CheckRun] = [
            .init(
                name: "build / unit tests", state: .failure, duration: .seconds(252), url: demoURL(id, "checks"),
                nodeID: "demo-unit-tests"),
            .init(name: "lint", state: .success, duration: .seconds(38), url: demoURL(id, "checks")),
            .init(name: "build / server", state: .success, duration: .seconds(171), url: demoURL(id, "checks")),
            .init(name: "danger", state: .pending, duration: nil, url: demoURL(id, "checks")),
        ]
        let commits: [Commit] = [
            Commit(
                sha: "9a1f04c3b2e1d0a9f8e7d6c5b4a39281706f5e4d", subject: "Add CSV encoder for invoices",
                body: "Encodes line items as RFC 4180 CSV.", author: lena, authoredAt: ago(30), isVerified: true,
                checkState: .success),
            Commit(
                sha: "3be7d12f0e9d8c7b6a5f4e3d2c1b0a9f8e7d6c5b", subject: "Add ExportFormat and export(_:as:)",
                author: lena, authoredAt: ago(28), isVerified: true, checkState: .success),
            Commit(
                sha: "c40e9a8d7c6b5a4f3e2d1c0b9a8f7e6d5c4b3a29", subject: "Sum invoice totals per line item",
                body: "Rounds each line before summing to match the PDF.", author: lena, authoredAt: ago(20),
                isVerified: true, checkState: .failure),
            Commit(
                sha: "e08b5a1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a", subject: "Address review: rename export types",
                author: jonas, authoredAt: ago(6), checkState: .failure),
        ]
        let summary = PullRequestSummary(
            id: id,
            title: id.number == 1234 ? "Add invoice export" : "Demo pull request #\(id.number)",
            author: lena,
            url: demoURL(id, ""),
            createdAt: ago(48),
            updatedAt: ago(2),
            additions: 182,
            deletions: 41,
            headRefName: "feature/invoice-export",
            baseRefName: "main",
            checkState: .failure,
            reviewDecision: .reviewRequired,
            mergeability: .mergeable
        )
        var detail = PullRequestDetail(
            summary: summary,
            body: """
                <!-- What does this change and why? -->
                ### What
                Adds **CSV export** next to JSON and changes how invoice totals are summed.

                - New `CSVEncoder` for line items
                - `export(_:as:)` takes an `ExportFormat`
                - Totals are now rounded per line item

                ### Checklist
                - [x] Tests added
                - [ ] Docs updated

                Closes #1180
                """,
            state: .open,
            headSHA: commits.last?.sha ?? "",
            baseSHA: "4a7d0b9e8f7a6b5c4d3e2f1a0b9c8d7e6f5a4b3c",
            headOwner: id.owner,
            changedFiles: 7,
            labels: [.init(name: "billing", color: "7B5BD6"), .init(name: "needs-qa", color: "E2B44F")],
            assignees: [lena],
            milestone: "2026.12",
            linkedIssues: [.init(number: 1180, title: "Export invoices as CSV", url: demoURL(id, "../../issues/1180"))],
            reviewers: [
                .init(name: jonas.login, user: jonas, isTeam: false, status: .approved),
                .init(name: marc.login, user: marc, isTeam: false, status: .pending),
                .init(name: "@acme/billing", user: nil, isTeam: true, status: .pending, isCodeOwner: true),
            ],
            mergeStatus: .derive(
                state: .open, mergeStateStatus: "BLOCKED", reviewDecision: .reviewRequired, checks: checks,
                isDraft: false),
            checks: checks,
            commits: commits
        )
        detail.approvalRules = ApprovalRules(requiredApprovals: 2, requiresCodeOwnerReview: true)
        detail.discussion = [
            DiscussionItem(
                id: "t1", place: .code(path: "Sources/Billing/InvoiceService.swift", line: 9, isResolved: false),
                author: jonas,
                body: "Rounding each line before summing can drift from the invoice total by a few "
                    + "cents. Should we round **once** at the end instead?",
                date: ago(5), url: demoURL(id, "#discussion_r1"),
                replies: [
                    .init(
                        author: lena, body: "Accounting wants per-line rounding to match the PDF (see BILL-311).",
                        date: ago(3))
                ]),
            DiscussionItem(
                id: "t2", place: .code(path: "Sources/Export/CSVEncoder.swift", line: 8, isResolved: true),
                author: marc, body: "Quote names with commas?", date: ago(30),
                replies: [.init(author: lena, body: "Done in 3be7d12.", date: ago(28))]),
            DiscussionItem(
                id: "c1", place: .conversation, author: lena,
                body: "Ready for review. The rounding change is the part that needs a careful look.", date: ago(26),
                url: demoURL(id, "#issuecomment-1")),
        ]
        if id.number == 1229 {
            // Demo for the "Involved" section: why the PR concerns the user.
            detail.involvement = Involvement(
                login: marc.login,
                mentions: [
                    Mention(
                        place: .codeComment(path: "Sources/Billing/Pricing/PriceRules.swift", line: 58),
                        author: jonas, date: ago(5),
                        excerpt:
                            "@mduu you wrote the VAT rounding — does it still hold when rules are split per market?",
                        url: demoURL(id, "#discussion_r1")),
                    Mention(
                        place: .comment, author: lena, date: ago(27),
                        excerpt: "Splitting this into two PRs would help. cc @mduu for the export part.",
                        url: demoURL(id, "#issuecomment-1")),
                ], ownCommentCount: 1, lastOwnCommentAt: ago(30), othersLastActivityAt: ago(3))
        }
        return detail
    }

    private static func demoURL(_ id: PullRequestID, _ suffix: String) -> URL? {
        URL(string: "https://github.com/\(id.owner)/\(id.repository)/pull/\(id.number)/\(suffix)")
    }
}
