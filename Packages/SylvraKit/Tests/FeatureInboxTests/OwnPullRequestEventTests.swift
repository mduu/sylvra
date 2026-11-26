import Foundation
import SylvraCore
import Testing

@testable import FeatureInbox

/// What the author of a pull request is told about: feedback by others and finished checks.
struct OwnPullRequestEventTests {
    static let now = Date(timeIntervalSince1970: 1_800_000_000)

    static func pullRequest(_ number: Int, checks: CheckState = .none, feedback: AuthorFeedback? = nil)
        -> PullRequestSummary
    {
        var summary = PullRequestSummary(
            id: PullRequestID(owner: "acme", repository: "billing", number: number), title: "Change \(number)",
            author: UserRef(login: "me"), createdAt: now, updatedAt: now, additions: 1, deletions: 0,
            headRefName: "feature", baseRefName: "main", checkState: checks)
        summary.authorFeedback = feedback
        return summary
    }

    static func snapshot(_ pullRequests: [PullRequestSummary], at date: Date = now) -> InboxSnapshot {
        InboxSnapshot(sections: [.myPullRequests: pullRequests], loadedAt: date)
    }

    @Test func tellsAboutNewFeedback() {
        let approval = AuthorFeedback(kind: .approved, at: Self.now.addingTimeInterval(60), by: "anna")
        let before = Self.snapshot([Self.pullRequest(1), Self.pullRequest(2, feedback: approval)])
        let after = Self.snapshot([Self.pullRequest(1, feedback: approval), Self.pullRequest(2, feedback: approval)])
        let events = after.ownPullRequestEvents(comparedTo: before)
        // #2's approval was known already.
        #expect(events.map(\.pullRequest.id.number) == [1])
        #expect(events.first?.kind == .feedback(approval))
        #expect(events.first?.message == "@anna approved")
    }

    @Test func tellsWhenRunningChecksFinish() {
        let before = Self.snapshot([
            Self.pullRequest(1, checks: .pending), Self.pullRequest(2, checks: .pending),
            Self.pullRequest(3, checks: .success),
        ])
        let after = Self.snapshot([
            Self.pullRequest(1, checks: .success), Self.pullRequest(2, checks: .failure),
            Self.pullRequest(3, checks: .success),
        ])
        #expect(after.ownPullRequestEvents(comparedTo: before).map(\.kind) == [.checksPassed, .checksFailed])
    }

    @Test func staysQuietAboutWhatWasThereBefore() {
        let old = AuthorFeedback(kind: .comment, at: Self.now.addingTimeInterval(-86_400), by: "ben")
        // A pull request the inbox didn't list before, and feedback from before this was tracked.
        let before = Self.snapshot([Self.pullRequest(2)])
        let after = Self.snapshot([Self.pullRequest(1, feedback: old), Self.pullRequest(2, feedback: old)])
        #expect(after.ownPullRequestEvents(comparedTo: before).isEmpty)
    }
}
