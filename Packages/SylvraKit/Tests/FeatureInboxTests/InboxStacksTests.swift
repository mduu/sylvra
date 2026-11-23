import Foundation
import SylvraCore
import Testing

@testable import FeatureInbox

struct InboxStacksTests {
    static func pr(
        _ number: Int, head: String, base: String, author: String = "lkeller", repository: String = "billing"
    ) -> PullRequestSummary {
        PullRequestSummary(
            id: PullRequestID(owner: "acme", repository: repository, number: number), title: "PR \(number)",
            author: UserRef(login: author), createdAt: .distantPast, updatedAt: .distantPast, additions: 1,
            deletions: 0, headRefName: head, baseRefName: base)
    }

    @Test func derivesAChainFromTheBranches() {
        let stacks = InboxStacks.derived(from: [
            Self.pr(3, head: "c", base: "b"), Self.pr(1, head: "a", base: "main"), Self.pr(2, head: "b", base: "a"),
            Self.pr(9, head: "x", base: "main"),
        ])
        #expect(stacks.count == 3)
        #expect(stacks[Self.pr(1, head: "a", base: "main").id]?.position == 1)
        #expect(stacks[Self.pr(3, head: "c", base: "b").id]?.position == 3)
        #expect(stacks[Self.pr(3, head: "c", base: "b").id]?.size == nil)
        #expect(Set(stacks.values.map(\.id)).count == 1)
    }

    @Test func aReleasePullRequestByAnotherAuthorIsNoLayer() {
        let stacks = InboxStacks.derived(from: [
            Self.pr(1, head: "develop", base: "main", author: "release-bot"), Self.pr(2, head: "f", base: "develop"),
        ])
        #expect(stacks.isEmpty)
    }

    @Test func twoPullRequestsOnOneBranchAreNoStack() {
        let stacks = InboxStacks.derived(from: [
            Self.pr(1, head: "a", base: "main"), Self.pr(2, head: "b", base: "a"), Self.pr(3, head: "c", base: "a"),
        ])
        #expect(stacks.isEmpty)
    }

    @Test func sameBranchNamesInOtherRepositoriesDontLink() {
        let stacks = InboxStacks.derived(from: [
            Self.pr(1, head: "a", base: "main"), Self.pr(2, head: "b", base: "a", repository: "payments"),
        ])
        #expect(stacks.isEmpty)
    }

    @Test func gitHubsStacksWinAndClosedPullRequestsDontDeriveOnes() {
        let bottom = Self.pr(1, head: "a", base: "main")
        let top = Self.pr(2, head: "b", base: "a")
        let native = [bottom.id: StackMembership(id: "github:7", position: 1, size: 3)]
        let sections = InboxStacks.annotate(
            [.requestedFromMe: [bottom], .myTeams: [top], .recentlyClosed: [Self.pr(5, head: "e", base: "b")]],
            native: native)
        #expect(sections[.requestedFromMe]?.first?.stack == native[bottom.id])
        #expect(sections[.myTeams]?.first?.stack == nil)
        #expect(sections[.recentlyClosed]?.first?.stack == nil)
    }

    @Test func groupsTheLayersBottomFirstWhereTheFirstOneIs() {
        func layer(_ number: Int, _ position: Int) -> PullRequestSummary {
            var pullRequest = Self.pr(number, head: "h\(number)", base: "main")
            pullRequest.stack = StackMembership(id: "s", position: position, size: 3)
            return pullRequest
        }
        let list = [
            Self.pr(10, head: "x", base: "main"), layer(3, 3), Self.pr(11, head: "y", base: "main"),
            layer(1, 1), layer(2, 2),
        ]
        #expect(InboxStacks.grouped(list).map(\.id.number) == [10, 1, 2, 3, 11])
    }
}
