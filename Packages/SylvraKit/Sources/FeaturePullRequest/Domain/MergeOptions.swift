import Foundation

/// How a pull request is merged on GitHub.
public enum MergeMethod: String, Sendable, CaseIterable, Identifiable {
    case merge = "MERGE"
    case squash = "SQUASH"
    case rebase = "REBASE"

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .merge: String(localized: "Create a merge commit")
        case .squash: String(localized: "Squash and merge")
        case .rebase: String(localized: "Rebase and merge")
        }
    }

    /// What it does to the base branch.
    public func explanation(commits: Int, base: String) -> String {
        switch self {
        case .merge: String(localized: "All \(commits) commits are added to \(base) with a merge commit.")
        case .squash: String(localized: "The \(commits) commits are combined into one commit on \(base).")
        case .rebase: String(localized: "The \(commits) commits are rebased and added to \(base).")
        }
    }
}

/// What the signed-in user may do to merge a pull request (from GitHub).
public struct MergeOptions: Sendable, Equatable {
    /// GitHub node ID of the pull request (the mutations need it).
    public var pullRequestNodeID: String
    /// The methods the repository allows, GitHub's default for the viewer first.
    public var methods: [MergeMethod]
    /// The viewer has write access to the repository.
    public var viewerCanMerge: Bool
    /// GitHub would merge on its own once the requirements are met (branch protection with auto-merge allowed).
    public var viewerCanEnableAutoMerge: Bool
    /// The viewer may merge although the branch rules are not met (GitHub: "bypass rules", merge as admin).
    public var viewerCanBypassRules: Bool
    /// Auto-merge is on, with this method.
    public var autoMerge: MergeMethod?

    public init(
        pullRequestNodeID: String, methods: [MergeMethod], viewerCanMerge: Bool,
        viewerCanEnableAutoMerge: Bool = false, viewerCanBypassRules: Bool = false, autoMerge: MergeMethod? = nil
    ) {
        self.viewerCanBypassRules = viewerCanBypassRules
        self.pullRequestNodeID = pullRequestNodeID
        self.methods = methods
        self.viewerCanMerge = viewerCanMerge
        self.viewerCanEnableAutoMerge = viewerCanEnableAutoMerge
        self.autoMerge = autoMerge
    }

    /// What the merge button offers for a merge status.
    public enum Action: Sendable, Equatable {
        /// Merge now.
        case merge
        /// Not mergeable yet: let GitHub merge once reviews and checks are through.
        case enableAutoMerge
        /// Auto-merge is on: it can be switched off.
        case disableAutoMerge
        /// Merge now although required reviews or checks are missing (hotfixes, trivial changes).
        case bypassRules
    }

    /// Whether merging past the branch rules is offered next to the regular action: only when the rules block
    /// the merge and the viewer may bypass them. Conflicts and drafts cannot be bypassed.
    public func canBypassRules(for status: MergeStatus) -> Bool {
        guard viewerCanMerge, viewerCanBypassRules, !methods.isEmpty else { return false }
        switch status.kind {
        case .blocked, .behind, .unstable, .unknown: return action(for: status) != .merge
        case .ready, .conflicts, .draft, .merged, .closed: return false
        }
    }

    /// The action for the pull request's state; `nil`: no button (merged, closed, no rights, nothing possible).
    public func action(for status: MergeStatus) -> Action? {
        guard viewerCanMerge, !methods.isEmpty else { return nil }
        if autoMerge != nil { return .disableAutoMerge }
        switch status.kind {
        case .ready, .unstable: return .merge
        case .blocked, .behind, .unknown: return viewerCanEnableAutoMerge ? .enableAutoMerge : nil
        case .conflicts, .draft, .merged, .closed: return nil
        }
    }
}
