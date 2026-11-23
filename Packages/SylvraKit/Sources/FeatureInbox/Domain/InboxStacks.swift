import Foundation
import SylvraCore

/// Stacks in the inbox: derives them from the listed pull requests when GitHub doesn't know them, and keeps the
/// layers of a stack together in a section.
enum InboxStacks {
    /// Stacks among `pullRequests` by their branches: a pull request builds on another when its base is the
    /// other's head, both are by the same author (a release pull request `develop → main` is no layer below every
    /// feature), and neither branch has a second candidate. Only the listed layers are known, so `size` is `nil`.
    static func derived(from pullRequests: [PullRequestSummary]) -> [PullRequestID: StackMembership] {
        var seen = Set<PullRequestID>()
        let unique = pullRequests.filter { seen.insert($0.id).inserted }
        func key(_ pullRequest: PullRequestSummary, _ branch: String) -> String {
            "\(pullRequest.id.owner)/\(pullRequest.id.repository)\u{0}\(pullRequest.author.login)\u{0}\(branch)"
        }
        let byHead = Dictionary(grouping: unique) { key($0, $0.headRefName) }
        let byBase = Dictionary(grouping: unique) { key($0, $0.baseRefName) }
        /// The only pull request building on `pullRequest`, when it is the only one on its base, too.
        func child(of pullRequest: PullRequestSummary) -> PullRequestSummary? {
            guard let children = byBase[key(pullRequest, pullRequest.headRefName)], children.count == 1,
                let child = children.first, byHead[key(pullRequest, pullRequest.headRefName)]?.count == 1
            else { return nil }
            return child
        }
        let children = Dictionary(
            unique.compactMap { pullRequest in child(of: pullRequest).map { ($0.id, pullRequest) } },
            uniquingKeysWith: { first, _ in first })
        var result: [PullRequestID: StackMembership] = [:]
        // Bottom layers: they build on something, but on nothing listed.
        for bottom in unique where children[bottom.id] == nil {
            var chain = [bottom]
            var visited: Set<PullRequestID> = [bottom.id]
            while let last = chain.last, let next = child(of: last), visited.insert(next.id).inserted {
                chain.append(next)
            }
            guard chain.count > 1 else { continue }
            let id = "branches:\(bottom.id)"
            for (index, layer) in chain.enumerated() {
                result[layer.id] = StackMembership(id: id, position: index + 1)
            }
        }
        return result
    }

    /// Sets `stack` where GitHub's (`native`) or else a derived membership is known.
    static func annotate(
        _ sections: [InboxSection: [PullRequestSummary]], native: [PullRequestID: StackMembership]
    ) -> [InboxSection: [PullRequestSummary]] {
        let open = sections.filter { $0.key != .recentlyClosed }.values.flatMap { $0 }
        let withoutNative = open.filter { native[$0.id] == nil }
        let derived = derived(from: withoutNative)
        return sections.mapValues { pullRequests in
            pullRequests.map { pullRequest in
                var pullRequest = pullRequest
                pullRequest.stack = native[pullRequest.id] ?? derived[pullRequest.id]
                return pullRequest
            }
        }
    }

    /// Moves the layers of a stack together, bottom first, where its first listed layer is. Everything else keeps
    /// its order.
    static func grouped(_ pullRequests: [PullRequestSummary]) -> [PullRequestSummary] {
        let layers = Dictionary(grouping: pullRequests.filter { $0.stack != nil }) { $0.stack?.id ?? "" }
        var placed = Set<String>()
        return pullRequests.flatMap { pullRequest -> [PullRequestSummary] in
            guard let stack = pullRequest.stack?.id else { return [pullRequest] }
            guard placed.insert(stack).inserted else { return [] }
            return (layers[stack] ?? []).sorted { ($0.stack?.position ?? 0) < ($1.stack?.position ?? 0) }
        }
    }
}
