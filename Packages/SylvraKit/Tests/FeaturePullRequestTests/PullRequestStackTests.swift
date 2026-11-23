import Foundation
import SylvraCore
import Testing

@testable import FeaturePullRequest

struct PullRequestStackTests {
    static func entry(
        _ number: Int, head: String, base: String, state: PullRequestDetail.State = .open
    ) -> PullRequestStack.Entry {
        PullRequestStack.Entry(
            summary: PullRequestSummary(
                id: PullRequestID(owner: "acme", repository: "billing", number: number), title: "PR \(number)",
                author: UserRef(login: "lkeller"), createdAt: .distantPast, updatedAt: .distantPast, additions: 1,
                deletions: 0, headRefName: head, baseRefName: base),
            state: state)
    }

    let bottom = entry(1, head: "a", base: "main")
    let middle = entry(2, head: "b", base: "a")
    let top = entry(3, head: "c", base: "b")

    @Test func ordersAlongTheBranchesBottomFirst() {
        let ordered = PullRequestStack.ordered([top, bottom, middle])
        #expect(ordered.map(\.id.number) == [1, 2, 3])
    }

    @Test func fallsBackToGitHubsPositionsWhenTheBranchesDontChain() {
        // The merged bottom layer's branch is gone from the chain: the middle one was retargeted to main.
        let merged = Self.entry(1, head: "a", base: "main", state: .merged)
        let retargeted = Self.entry(2, head: "b", base: "main")
        let positions = [merged.id: 1, retargeted.id: 2, top.id: 3]
        let ordered = PullRequestStack.ordered([top, retargeted, merged], positions: positions)
        #expect(ordered.map(\.id.number) == [1, 2, 3])
    }

    @Test func knowsNeighboursAndWhetherTheBranchNeedsARestack() {
        let stack = PullRequestStack(source: .gitHub, trunk: "main", entries: [bottom, middle, top])
        var status = StackStatus(stack: stack, current: middle.id, commitsBehindParent: 2)
        #expect(status.position == 2)
        #expect(status.size == 3)
        #expect(status.parent?.id == bottom.id)
        #expect(status.child?.id == top.id)
        #expect(status.isParentOpen)
        #expect(status.needsRestack)

        status.commitsBehindParent = 0
        #expect(!status.needsRestack)

        let atBottom = StackStatus(stack: stack, current: bottom.id, commitsBehindParent: 2)
        #expect(atBottom.parent == nil)
        #expect(!atBottom.isParentOpen)
        #expect(!atBottom.needsRestack)
    }

    @Test func aMergedParentNeedsNoRestack() {
        let merged = Self.entry(1, head: "a", base: "main", state: .merged)
        let stack = PullRequestStack(source: .gitHub, trunk: "main", entries: [merged, middle])
        let status = StackStatus(stack: stack, current: middle.id, commitsBehindParent: 4)
        #expect(!status.isParentOpen)
        #expect(!status.needsRestack)
    }
}

struct BranchStackWalkerTests {
    /// Open pull requests by branch, like the GitHub queries return them.
    static func walker(_ pullRequests: [PullRequestStack.Entry], defaultBranch: String? = "main")
        -> BranchStackWalker
    {
        BranchStackWalker(
            pullRequestsWithHead: { branch in pullRequests.filter { $0.summary.headRefName == branch } },
            pullRequestsWithBase: { branch in pullRequests.filter { $0.summary.baseRefName == branch } },
            defaultBranch: defaultBranch)
    }

    let bottom = PullRequestStackTests.entry(1, head: "a", base: "main")
    let middle = PullRequestStackTests.entry(2, head: "b", base: "a")
    let top = PullRequestStackTests.entry(3, head: "c", base: "b")

    @Test func findsTheLayersBelowAndAbove() async throws {
        let stack = try await Self.walker([bottom, middle, top]).stack(around: middle)
        #expect(stack?.entries.map(\.id.number) == [1, 2, 3])
        #expect(stack?.trunk == "main")
        #expect(stack?.source == .branches)
    }

    @Test func aPullRequestOnItsOwnIsNoStack() async throws {
        let lonely = PullRequestStackTests.entry(9, head: "x", base: "main")
        #expect(try await Self.walker([lonely, bottom]).stack(around: lonely) == nil)
    }

    @Test func stopsWhereSeveralPullRequestsTargetABranch() async throws {
        // Two pull requests build on `b`: which one continues the stack is a guess, so it ends at the middle.
        let other = PullRequestStackTests.entry(4, head: "d", base: "b")
        let stack = try await Self.walker([bottom, middle, top, other]).stack(around: middle)
        #expect(stack?.entries.map(\.id.number) == [1, 2])
    }

    @Test func anIntegrationBranchIsNoLayer() async throws {
        // A release pull request `develop → main` and two features on `develop`: no stacks.
        let release = PullRequestStackTests.entry(10, head: "develop", base: "main")
        let feature = PullRequestStackTests.entry(11, head: "f1", base: "develop")
        let otherFeature = PullRequestStackTests.entry(12, head: "f2", base: "develop")
        let walker = Self.walker([release, feature, otherFeature])
        #expect(try await walker.stack(around: feature) == nil)
    }

    @Test func survivesBranchCycles() async throws {
        let first = PullRequestStackTests.entry(1, head: "a", base: "b")
        let second = PullRequestStackTests.entry(2, head: "b", base: "a")
        let stack = try await Self.walker([first, second], defaultBranch: nil).stack(around: first)
        #expect(stack?.entries.count == 2)
    }
}
