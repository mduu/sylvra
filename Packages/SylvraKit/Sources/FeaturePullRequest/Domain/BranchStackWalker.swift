import Foundation
import SylvraCore

/// Derives a stack from branches when GitHub doesn't know one: walks down while the base branch is the head of
/// exactly one other open pull request (and only this one targets it), and up while exactly one open pull request
/// targets the head branch.
/// Ambiguous spots (several pull requests on one branch) end the walk: a guess would be worse than a shorter stack.
struct BranchStackWalker: Sendable {
    /// Open pull requests of the same repository (no forks) whose head branch is the given one.
    let pullRequestsWithHead: @Sendable (String) async throws -> [PullRequestStack.Entry]
    /// Open pull requests of the same repository (no forks) that target the given branch.
    let pullRequestsWithBase: @Sendable (String) async throws -> [PullRequestStack.Entry]
    /// The repository's default branch: never the head of a layer, so the walk down stops there for free.
    var defaultBranch: String?
    var maxDepth = 8

    /// The stack around `current`, or `nil` when it builds on nothing and nothing builds on it.
    func stack(around current: PullRequestStack.Entry) async throws -> PullRequestStack? {
        var visited: Set<PullRequestID> = [current.id]
        var below: [PullRequestStack.Entry] = []
        var base = current.summary.baseRefName
        while below.count < maxDepth, base != defaultBranch {
            let branch = base
            async let candidates = pullRequestsWithHead(branch)
            // A branch several pull requests target is an integration branch (`develop`, a release branch), not
            // a layer: a release pull request `develop → main` doesn't make every feature a stack.
            async let siblings = pullRequestsWithBase(branch)
            let parents = try await candidates.filter { !visited.contains($0.id) }
            guard parents.count == 1, let parent = parents.first, try await siblings.count == 1 else { break }
            visited.insert(parent.id)
            below.insert(parent, at: 0)
            base = parent.summary.baseRefName
        }
        var above: [PullRequestStack.Entry] = []
        var head = current.summary.headRefName
        while above.count < maxDepth {
            let children = try await pullRequestsWithBase(head).filter { !visited.contains($0.id) }
            guard children.count == 1, let child = children.first else { break }
            visited.insert(child.id)
            above.append(child)
            head = child.summary.headRefName
        }
        let entries = below + [current] + above
        guard entries.count > 1, let bottom = entries.first else { return nil }
        return PullRequestStack(source: .branches, trunk: bottom.summary.baseRefName, entries: entries)
    }
}
