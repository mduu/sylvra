import Foundation
import SylvraCore

/// Pull requests that build on each other: the bottom one targets the trunk (usually the default branch), every
/// other one targets the branch of the pull request below it.
public struct PullRequestStack: Sendable, Equatable {
    /// Where the stack comes from.
    public enum Source: Sendable, Equatable {
        /// A stack GitHub knows (created with `gh stack` or on github.com).
        case gitHub
        /// Derived from the base and head branches of open pull requests (Graphite, git-town, by hand …).
        case branches
    }

    public struct Entry: Sendable, Equatable, Identifiable {
        public var id: PullRequestID { summary.id }
        public var summary: PullRequestSummary
        public var state: PullRequestDetail.State
        /// The head commit; `nil` when unknown.
        public var headSHA: String?

        public init(summary: PullRequestSummary, state: PullRequestDetail.State, headSHA: String? = nil) {
            self.summary = summary
            self.state = state
            self.headSHA = headSHA
        }
    }

    public var source: Source
    /// The branch the bottom pull request targets.
    public var trunk: String
    /// Bottom (next to the trunk) first.
    public var entries: [Entry]

    public init(source: Source, trunk: String, entries: [Entry]) {
        self.source = source
        self.trunk = trunk
        self.entries = entries
    }

    public func index(of id: PullRequestID) -> Int? { entries.firstIndex { $0.id == id } }

    /// The pull request this one builds on (`nil` for the bottom one).
    public func parent(of id: PullRequestID) -> Entry? {
        guard let index = index(of: id), index > 0 else { return nil }
        return entries[index - 1]
    }

    /// The pull request that builds on this one (`nil` for the top one).
    public func child(of id: PullRequestID) -> Entry? {
        guard let index = index(of: id), index + 1 < entries.count else { return nil }
        return entries[index + 1]
    }

    /// Orders entries along their branches, bottom first: each entry's base is the head of the one before.
    /// Entries that don't fit the chain (e.g. a merged layer whose base was retargeted) keep GitHub's order
    /// (`positions`, ascending) and are placed by that.
    public static func ordered(_ entries: [Entry], positions: [PullRequestID: Int] = [:]) -> [Entry] {
        let byPosition = entries.sorted { (positions[$0.id] ?? 0) < (positions[$1.id] ?? 0) }
        let heads = Set(entries.map(\.summary.headRefName))
        // The bottom builds on a branch no other entry provides.
        guard let bottom = byPosition.first(where: { !heads.contains($0.summary.baseRefName) }) else {
            return byPosition
        }
        var chain = [bottom]
        var remaining = byPosition.filter { $0.id != bottom.id }
        while let last = chain.last,
            let next = remaining.firstIndex(where: { $0.summary.baseRefName == last.summary.headRefName })
        {
            chain.append(remaining.remove(at: next))
        }
        guard !remaining.isEmpty else { return chain }
        // Not a clean chain: GitHub's positions are the better guess.
        return positions.isEmpty ? chain + remaining : byPosition
    }
}

/// The stack around the pull request shown, with what the reviewer should know about it.
public struct StackStatus: Sendable, Equatable {
    public var stack: PullRequestStack
    public var current: PullRequestID
    /// Commits on the parent's branch this pull request doesn't include yet (`nil`: unknown or no parent). More
    /// than zero means the branch needs a restack: the diff doesn't show the parent's latest state.
    public var commitsBehindParent: Int?

    public init(stack: PullRequestStack, current: PullRequestID, commitsBehindParent: Int? = nil) {
        self.stack = stack
        self.current = current
        self.commitsBehindParent = commitsBehindParent
    }

    /// 1-based layer, counted from the trunk.
    public var position: Int { (stack.index(of: current) ?? 0) + 1 }
    public var size: Int { stack.entries.count }
    public var parent: PullRequestStack.Entry? { stack.parent(of: current) }
    public var child: PullRequestStack.Entry? { stack.child(of: current) }

    /// The parent is still open: this pull request can only merge after it.
    public var isParentOpen: Bool { parent?.state == .open }

    public var needsRestack: Bool { (commitsBehindParent ?? 0) > 0 && isParentOpen }
}
