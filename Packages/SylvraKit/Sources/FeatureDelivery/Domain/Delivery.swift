import Foundation
import SylvraCore

/// Where a stage or job of a delivery stands.
public enum StageState: String, Sendable, Codable {
    case waiting, needsApproval, running, succeeded, failed, cancelled, skipped

    /// Nothing more will happen here.
    public var isFinished: Bool {
        switch self {
        case .succeeded, .failed, .cancelled, .skipped: true
        case .waiting, .needsApproval, .running: false
        }
    }

    public var title: String {
        switch self {
        case .waiting: String(localized: "Waiting")
        case .needsApproval: String(localized: "Needs approval")
        case .running: String(localized: "Running")
        case .succeeded: String(localized: "Done")
        case .failed: String(localized: "Failed")
        case .cancelled: String(localized: "Cancelled")
        case .skipped: String(localized: "Skipped")
        }
    }
}

/// One job of a workflow run.
public struct DeliveryJob: Identifiable, Hashable, Sendable {
    public let id: String
    public var name: String
    public let state: StageState
    public let startedAt: Date?
    public let finishedAt: Date?
    public let url: URL?
    /// The steps that failed, in order.
    public var failedSteps: [String]
    /// What the job reported as errors (its failure annotations).
    public var errors: [String]

    public init(
        id: String, name: String, state: StageState, startedAt: Date? = nil, finishedAt: Date? = nil,
        url: URL? = nil, failedSteps: [String] = [], errors: [String] = []
    ) {
        self.id = id
        self.name = name
        self.state = state
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.url = url
        self.failedSteps = failedSteps
        self.errors = errors
    }

    public var duration: TimeInterval? {
        guard let startedAt, let finishedAt else { return nil }
        return max(0, finishedAt.timeIntervalSince(startedAt))
    }
}

/// One step of the way to production: the build, or a deployment to an environment.
public struct DeliveryStage: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable {
        /// The jobs of a workflow that deploy nowhere (build, tests, packaging).
        case build
        /// A deployment to an environment (dev, test, prod …).
        case environment
    }

    /// A deployment that waits for someone's approval on GitHub.
    public struct Approval: Hashable, Sendable {
        public let workflowRunID: String
        public let environmentID: String
        /// The signed-in user is one of the reviewers of the environment.
        public let viewerCanApprove: Bool

        public init(workflowRunID: String, environmentID: String, viewerCanApprove: Bool) {
            self.workflowRunID = workflowRunID
            self.environmentID = environmentID
            self.viewerCanApprove = viewerCanApprove
        }
    }

    public let id: String
    public let name: String
    public let kind: Kind
    /// The workflow it belongs to (`nil`: reported by another system as a deployment).
    public let workflow: String?
    public let state: StageState
    public var jobs: [DeliveryJob]
    public var startedAt: Date?
    public var finishedAt: Date?
    /// The workflow run or deployment on GitHub.
    public var url: URL?
    public var approval: Approval?

    public init(
        id: String, name: String, kind: Kind, workflow: String?, state: StageState, jobs: [DeliveryJob] = [],
        startedAt: Date? = nil, finishedAt: Date? = nil, url: URL? = nil, approval: Approval? = nil
    ) {
        self.id = id
        self.name = name
        self.kind = kind
        self.workflow = workflow
        self.state = state
        self.jobs = jobs
        self.startedAt = startedAt
        self.finishedAt = finishedAt
        self.url = url
        self.approval = approval
    }

    public var duration: TimeInterval? {
        guard let startedAt, let finishedAt else { return nil }
        return max(0, finishedAt.timeIntervalSince(startedAt))
    }

    /// The state of a stage from its jobs: a failure wins, then what still runs or waits.
    public static func state(of jobs: [StageState]) -> StageState {
        if jobs.contains(.failed) { return .failed }
        if jobs.contains(.needsApproval) { return .needsApproval }
        if jobs.contains(.running) { return .running }
        if jobs.contains(.waiting) { return jobs.contains(.succeeded) ? .running : .waiting }
        if jobs.contains(.cancelled) { return .cancelled }
        if jobs.contains(.succeeded) { return .succeeded }
        return jobs.isEmpty ? .waiting : .skipped
    }
}

/// A merged pull request on its way to production: the stages GitHub knows for its merge commit.
public struct Delivery: Hashable, Sendable {
    public let pullRequest: PullRequestID
    public let title: String
    public let mergeCommitSHA: String
    public let mergedAt: Date?
    public var stages: [DeliveryStage]

    public init(
        pullRequest: PullRequestID, title: String, mergeCommitSHA: String, mergedAt: Date?, stages: [DeliveryStage]
    ) {
        self.pullRequest = pullRequest
        self.title = title
        self.mergeCommitSHA = mergeCommitSHA
        self.mergedAt = mergedAt
        self.stages = stages
    }

    /// How long after the merge a missing deployment counts as "none started".
    public static let startGrace: TimeInterval = 300

    /// Every stage is through (none: only once the grace time after the merge has passed).
    public func isFinished(at now: Date = .now) -> Bool {
        if stages.isEmpty { return now.timeIntervalSince(mergedAt ?? now) > Self.startGrace }
        return stages.allSatisfy(\.state.isFinished)
    }

    /// The stage to show first: the failed one, else the one that runs or waits, else the last.
    public var currentStage: DeliveryStage? {
        stages.first { $0.state == .failed } ?? stages.first { !$0.state.isFinished } ?? stages.last
    }

    /// The stage that is production: the last environment named like it, else the last environment.
    public var productionStage: DeliveryStage? {
        let environments = stages.filter { $0.kind == .environment }
        return environments.last { stage in
            let name = stage.name.lowercased()
            return ["prod", "prd", "live"].contains { name.contains($0) }
        } ?? environments.last
    }

    /// One line for the whole delivery, e.g. "prod failed" or "Deployed to prod".
    public func headline(at now: Date = .now) -> String {
        if let failed = stages.first(where: { $0.state == .failed }) {
            return String(localized: "\(failed.name) failed")
        }
        if let waiting = stages.first(where: { $0.state == .needsApproval }) {
            return String(localized: "\(waiting.name) waits for approval")
        }
        if let running = stages.first(where: { $0.state == .running }) {
            return String(localized: "\(running.name) is running")
        }
        if stages.isEmpty {
            return isFinished(at: now)
                ? String(localized: "No deployment started") : String(localized: "Waiting for the deployment to start")
        }
        if stages.contains(where: { $0.state == .waiting }) { return String(localized: "Waiting") }
        if let last = stages.last(where: { $0.kind == .environment && $0.state == .succeeded }) {
            return String(localized: "Deployed to \(last.name)")
        }
        return stages.contains { $0.state == .cancelled }
            ? String(localized: "Cancelled") : String(localized: "All stages done")
    }

    /// The overall state shown next to the headline.
    public func overallState(at now: Date = .now) -> StageState {
        if stages.isEmpty { return isFinished(at: now) ? .skipped : .waiting }
        return DeliveryStage.state(of: stages.map(\.state))
    }
}

/// Something that happened to a followed delivery and is worth a notification.
public struct DeliveryEvent: Hashable, Sendable {
    public enum Kind: Hashable, Sendable {
        case stageSucceeded(String), stageFailed(String), needsApproval(String)
        /// The AI check of a stage is through.
        case verified(String, StageVerification.Verdict)
        /// Every stage is through and nothing new started.
        case complete
        /// Nothing started for the merge commit.
        case nothingStarted
    }

    public let pullRequest: PullRequestID
    public let title: String
    public let kind: Kind

    public var message: String {
        switch kind {
        case .stageSucceeded(let name): String(localized: "\(name) done")
        case .stageFailed(let name): String(localized: "\(name) failed")
        case .needsApproval(let name): String(localized: "\(name) waits for approval")
        case .verified(let name, let verdict):
            switch verdict {
            case .healthy: String(localized: "\(name) checked: healthy")
            case .problems: String(localized: "\(name) checked: problems found")
            case .unchecked: String(localized: "\(name) could not be checked")
            }
        case .complete: String(localized: "Delivery complete")
        case .nothingStarted: String(localized: "No deployment started")
        }
    }

    /// The stages that changed to done, failed or waiting for approval between two loads.
    public static func changes(from old: Delivery?, to new: Delivery) -> [DeliveryEvent] {
        guard let old else { return [] }
        let before = Dictionary(old.stages.map { ($0.id, $0.state) }, uniquingKeysWith: { first, _ in first })
        return new.stages.compactMap { stage -> DeliveryEvent? in
            guard before[stage.id] != stage.state else { return nil }
            let kind: Kind? =
                switch stage.state {
                case .succeeded: .stageSucceeded(stage.name)
                case .failed: .stageFailed(stage.name)
                case .needsApproval: .needsApproval(stage.name)
                default: nil
                }
            return kind.map { DeliveryEvent(pullRequest: new.pullRequest, title: new.title, kind: $0) }
        }
    }
}
