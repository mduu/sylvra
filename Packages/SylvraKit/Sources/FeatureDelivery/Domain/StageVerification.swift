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

        public init(title: String, outcome: Outcome, finding: String, evidence: String? = nil) {
            self.title = title
            self.outcome = outcome
            self.finding = finding
            self.evidence = evidence
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
