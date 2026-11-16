import Foundation
import SylvraCore

/// Everything shown in the PR column (see specs/ux.md §6).
public struct PullRequestDetail: Sendable, Equatable {
    public var summary: PullRequestSummary
    public var body: String
    public var state: State
    public var headSHA: String
    public var baseSHA: String
    public var headOwner: String?
    public var changedFiles: Int
    public var labels: [Label]
    public var assignees: [UserRef]
    public var milestone: String?
    public var linkedIssues: [LinkedIssue]
    public var reviewers: [Reviewer]
    public var mergeStatus: MergeStatus
    public var checks: [CheckRun]
    public var commits: [Commit]
    /// Where the signed-in user was mentioned or took part.
    public var involvement = Involvement()

    public enum State: String, Sendable {
        case open = "OPEN", closed = "CLOSED", merged = "MERGED"
    }

    public struct Label: Hashable, Sendable {
        public let name: String
        /// Hex color without `#`.
        public let color: String
    }

    public struct LinkedIssue: Hashable, Sendable {
        public let number: Int
        public let title: String
        public let url: URL?
    }

    /// A reviewer and their latest review state (or a pending request).
    public struct Reviewer: Hashable, Sendable, Identifiable {
        public enum Status: String, Sendable {
            case approved = "APPROVED"
            case changesRequested = "CHANGES_REQUESTED"
            case commented = "COMMENTED"
            case dismissed = "DISMISSED"
            case pending = "PENDING"
        }

        public var id: String { name }
        public let name: String
        public let user: UserRef?
        public let isTeam: Bool
        public let status: Status
    }

    public struct CheckRun: Hashable, Sendable, Identifiable {
        public var id: String { name }
        public let name: String
        public let state: CheckState
        public let duration: Duration?
        public let url: URL?
        /// GitHub node ID of a check run (loads its report); `nil` for commit statuses.
        public var nodeID: String?
        /// Description of a commit status (statuses have no report).
        public var statusDescription: String?
    }
}

/// What a check run reported: GitHub's "Summary" of the run plus its annotations.
public struct CheckReport: Sendable, Equatable {
    public struct Annotation: Sendable, Equatable, Identifiable {
        public enum Level: String, Sendable {
            case failure = "FAILURE", warning = "WARNING", notice = "NOTICE"
        }

        public var id: String { "\(path):\(line ?? 0):\(message.prefix(40))" }
        public let path: String
        public let line: Int?
        public let level: Level
        public let title: String?
        public let message: String

        public init(path: String, line: Int?, level: Level, title: String?, message: String) {
            self.path = path
            self.line = line
            self.level = level
            self.title = title
            self.message = message
        }
    }

    public var title: String?
    /// Markdown summary written by the check.
    public var summary: String?
    /// Markdown details (often logs or test output).
    public var text: String?
    public var annotations: [Annotation]

    public init(title: String? = nil, summary: String? = nil, text: String? = nil, annotations: [Annotation] = []) {
        self.title = title
        self.summary = summary
        self.text = text
        self.annotations = annotations
    }

    public var isEmpty: Bool {
        [title, summary, text].allSatisfy { ($0 ?? "").trimmingCharacters(in: .whitespacesAndNewlines).isEmpty }
            && annotations.isEmpty
    }
}

/// GitHub's merge state, expressed as reasons the reviewer understands.
public struct MergeStatus: Sendable, Equatable {
    public enum Kind: Sendable, Equatable {
        case ready, blocked, conflicts, behind, unstable, draft, merged, closed, unknown
    }

    public var kind: Kind
    public var reasons: [String]

    public init(kind: Kind, reasons: [String] = []) {
        self.kind = kind
        self.reasons = reasons
    }

    /// Derives the status from GitHub's fields (`mergeStateStatus`, review decision, checks).
    public static func derive(
        state: PullRequestDetail.State,
        mergeStateStatus: String?,
        reviewDecision: ReviewDecision,
        checks: [PullRequestDetail.CheckRun],
        isDraft: Bool
    ) -> MergeStatus {
        if state == .merged { return MergeStatus(kind: .merged) }
        if state == .closed { return MergeStatus(kind: .closed) }
        if isDraft { return MergeStatus(kind: .draft, reasons: [String(localized: "Pull request is a draft")]) }

        let reasons = blockingReasons(reviewDecision: reviewDecision, checks: checks)
        switch mergeStateStatus {
        case "CLEAN", "HAS_HOOKS": return MergeStatus(kind: .ready)
        case "DIRTY": return MergeStatus(kind: .conflicts, reasons: [String(localized: "Merge conflicts")] + reasons)
        case "BEHIND":
            return MergeStatus(
                kind: .behind, reasons: [String(localized: "Branch is behind the base branch")] + reasons)
        case "UNSTABLE": return MergeStatus(kind: .unstable, reasons: reasons)
        case "BLOCKED": return MergeStatus(kind: .blocked, reasons: reasons)
        default: return MergeStatus(kind: reasons.isEmpty ? .unknown : .blocked, reasons: reasons)
        }
    }

    private static func blockingReasons(reviewDecision: ReviewDecision, checks: [PullRequestDetail.CheckRun])
        -> [String]
    {
        var reasons: [String] = []
        if reviewDecision == .reviewRequired { reasons.append(String(localized: "Approving review required")) }
        if reviewDecision == .changesRequested { reasons.append(String(localized: "Changes requested")) }
        let failing = checks.filter { $0.state == .failure || $0.state == .error }
        if !failing.isEmpty {
            reasons.append(String(localized: "\(failing.count) check(s) failing"))
        }
        return reasons
    }
}
