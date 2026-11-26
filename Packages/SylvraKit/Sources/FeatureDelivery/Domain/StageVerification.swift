import Foundation
import SylvraCore

/// What an AI agent found when it checked one stage of a delivery in logs and monitoring: an assessment with
/// its evidence, not a fact (see specs/delivery.md §3).
public struct StageVerification: Hashable, Sendable, Codable {
    public enum Verdict: String, Sendable, Codable {
        /// Deployed and no sign of trouble in what could be checked.
        case healthy
        /// Something is wrong: the deployment failed or the deployed change shows errors.
        case problems
        /// Nothing meaningful could be checked (no tools, no signal).
        case unchecked

        public var title: String {
            switch self {
            case .healthy: String(localized: "Healthy")
            case .problems: String(localized: "Problems found")
            case .unchecked: String(localized: "Could not be checked")
            }
        }
    }

    /// One thing the agent looked at.
    public struct Check: Hashable, Sendable, Codable, Identifiable {
        public enum Outcome: String, Sendable, Codable {
            case ok, problem, unchecked
        }

        public var id: String { title }
        public let title: String
        public let outcome: Outcome
        /// What it means, in a sentence or two.
        public let finding: String
        /// What was looked at: tool, query, time window, figures before and after.
        public let evidence: String?
        /// The query or command, as run (shown in a code box).
        public var query: String?
        /// The figure before and after the deployment, e.g. "14 matches" / "0 matches".
        public var before: String?
        public var after: String?
        /// The lines of the log or output that show it (a short excerpt).
        public var excerpt: [String]

        public init(
            title: String, outcome: Outcome, finding: String, evidence: String? = nil, query: String? = nil,
            before: String? = nil, after: String? = nil, excerpt: [String] = []
        ) {
            self.title = title
            self.outcome = outcome
            self.finding = finding
            self.evidence = evidence
            self.query = query
            self.before = before
            self.after = after
            self.excerpt = excerpt
        }

        enum CodingKeys: String, CodingKey {
            case title, outcome, finding, evidence, query, before, after, excerpt
        }

        public init(from decoder: any Decoder) throws {
            let container = try decoder.container(keyedBy: CodingKeys.self)
            title = try container.decode(String.self, forKey: .title)
            outcome = try container.decode(Outcome.self, forKey: .outcome)
            finding = try container.decode(String.self, forKey: .finding)
            evidence = try container.decodeIfPresent(String.self, forKey: .evidence)
            query = try container.decodeIfPresent(String.self, forKey: .query)
            before = try container.decodeIfPresent(String.self, forKey: .before)
            after = try container.decodeIfPresent(String.self, forKey: .after)
            excerpt = try container.decodeIfPresent([String].self, forKey: .excerpt) ?? []
        }
    }

    public let stageID: String
    public let stageName: String
    public let verdict: Verdict
    /// The result in one or two sentences.
    public let summary: String
    /// What the change is meant to fix or introduce, as the agent understood it.
    public let intent: String
    public let checks: [Check]
    /// Points that could not be checked, with the reason.
    public let notChecked: [String]
    public let checkedAt: Date
    /// A later look at the same stage (production gets one after a while).
    public var isSecondLook: Bool
    /// What the agent did, in order (tools it called with what), for *What the agent did*.
    public var activity: [String] = []
    /// Tools the agent tried but Claude Code did not allow (full names, e.g. `mcp__datadog__search_logs`).
    public var deniedTools: [String] = []

    enum CodingKeys: String, CodingKey {
        case stageID, stageName, verdict, summary, intent, checks, notChecked, checkedAt, isSecondLook, activity
        case deniedTools
    }

    /// Results saved by an earlier version lack the newer fields.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        stageID = try container.decode(String.self, forKey: .stageID)
        stageName = try container.decode(String.self, forKey: .stageName)
        verdict = try container.decode(Verdict.self, forKey: .verdict)
        summary = try container.decode(String.self, forKey: .summary)
        intent = try container.decodeIfPresent(String.self, forKey: .intent) ?? ""
        checks = try container.decodeIfPresent([Check].self, forKey: .checks) ?? []
        notChecked = try container.decodeIfPresent([String].self, forKey: .notChecked) ?? []
        checkedAt = try container.decode(Date.self, forKey: .checkedAt)
        isSecondLook = try container.decodeIfPresent(Bool.self, forKey: .isSecondLook) ?? false
        activity = try container.decodeIfPresent([String].self, forKey: .activity) ?? []
        deniedTools = try container.decodeIfPresent([String].self, forKey: .deniedTools) ?? []
    }

    public init(
        stageID: String, stageName: String, verdict: Verdict, summary: String, intent: String = "",
        checks: [Check] = [], notChecked: [String] = [], checkedAt: Date = .now, isSecondLook: Bool = false
    ) {
        self.stageID = stageID
        self.stageName = stageName
        self.verdict = verdict
        self.summary = summary
        self.intent = intent
        self.checks = checks
        self.notChecked = notChecked
        self.checkedAt = checkedAt
        self.isSecondLook = isSecondLook
    }
}

/// What the agent needs to check a stage.
public struct VerificationRequest: Sendable {
    public let pullRequest: PullRequestID
    public let title: String
    /// The pull request's description.
    public let body: String
    public let delivery: Delivery
    public let stage: DeliveryStage
    /// What the user noted about this repository's monitoring (service names, environments, dashboards).
    public let monitoringNotes: String
    public let isSecondLook: Bool
    /// Tools the user allowed for AI checks in Sylvra (full names), on top of the read-only `gh` / `git` commands.
    public var allowedTools: [String] = []

    public init(
        pullRequest: PullRequestID, title: String, body: String, delivery: Delivery, stage: DeliveryStage,
        monitoringNotes: String = "", isSecondLook: Bool = false
    ) {
        self.pullRequest = pullRequest
        self.title = title
        self.body = body
        self.delivery = delivery
        self.stage = stage
        self.monitoringNotes = monitoringNotes
        self.isSecondLook = isSecondLook
    }
}
