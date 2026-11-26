import Foundation
import Observation
import Platform
import SylvraCore

/// The deliveries Sylvra shows and follows: a merged pull request's stages from GitHub, reloaded while shown,
/// and — for followed ones — also in the background, with an event per stage (see specs/delivery.md).
@MainActor
@Observable
public final class DeliveryModel {
    public enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    public private(set) var deliveries: [PullRequestID: Delivery] = [:]
    public private(set) var loadState: LoadState = .idle
    /// The pull requests whose deliveries are followed in the background (persisted).
    public private(set) var followed: [PullRequestID] = []
    /// The stage whose card is shown, per pull request (`nil`: the current one).
    public var selectedStage: [PullRequestID: String] = [:]
    /// An approval is being sent to GitHub.
    public private(set) var isApproving = false
    /// Why GitHub refused the last approval.
    public private(set) var approvalError: String?
    /// Called for followed deliveries when a stage finishes, fails or waits for approval (wired by the app
    /// for notifications).
    @ObservationIgnored public var onEvent: ((DeliveryEvent) -> Void)?

    // Verification (see DeliveryModel+Verification).
    /// What the agent found per stage (`stage.id`), per pull request (persisted).
    public internal(set) var verifications: [PullRequestID: [String: StageVerification]] = [:]
    /// The stages being verified right now (`verificationKey`).
    public internal(set) var verifying: Set<String> = []
    /// Why the last verification of a stage failed (`verificationKey`).
    public internal(set) var verificationErrors: [String: String] = [:]
    /// Followed deliveries are verified without a click: each deployed stage after a settling time, a failed
    /// one at once (persisted; off by default).
    public var verifiesAutomatically: Bool {
        didSet { defaults?.set(verifiesAutomatically, forKey: Self.autoVerifyKey) }
    }
    /// Title and description of a pull request for the agent (wired by the app).
    @ObservationIgnored public var pullRequestInfo: ((PullRequestID) async -> DeliveryPullRequestInfo?)?
    /// Verifications that are due later (in memory: a restart drops them).
    @ObservationIgnored var scheduled: [ScheduledVerification] = []
    let verifier: (any DeliveryVerifying)?
    let cache: JSONCache?

    private let loader: any DeliveryLoading
    let defaults: UserDefaults?
    /// Since when a followed delivery has had nothing left to do (a chained workflow may still start).
    @ObservationIgnored private var settledSince: [PullRequestID: Date] = [:]
    private static let logger = SylvraLog.logger("delivery")
    static let followedKey = "delivery.followed"
    /// How often a delivery is reloaded while it is shown or followed.
    public static let refreshInterval: Duration = .seconds(30)
    /// How long a finished delivery is still followed, for workflows started by the finished ones.
    static let settleTime: TimeInterval = 300
    /// Followed at most this long after the merge.
    static let followLimit: TimeInterval = 86_400

    /// - Parameters:
    ///   - verifier: checks stages with an AI agent; `nil` hides everything about verification.
    ///   - cache: keeps the verifications across launches.
    public init(
        loader: any DeliveryLoading, verifier: (any DeliveryVerifying)? = nil, defaults: UserDefaults? = nil,
        cache: JSONCache? = nil
    ) {
        self.loader = loader
        self.verifier = verifier
        self.defaults = defaults
        self.cache = cache
        verifiesAutomatically = defaults?.bool(forKey: Self.autoVerifyKey) ?? false
        if let saved = cache?.load([String: [StageVerification]].self, key: Self.verificationsKey) {
            for (text, results) in saved {
                guard let id = PullRequestID(text) else { continue }
                verifications[id] = Dictionary(results.map { ($0.stageID, $0) }, uniquingKeysWith: { $1 })
            }
        }
        followed = (defaults?.stringArray(forKey: Self.followedKey) ?? []).compactMap(PullRequestID.init)
    }

    // MARK: Loading

    public func delivery(for id: PullRequestID?) -> Delivery? { id.flatMap { deliveries[$0] } }

    /// Loads the delivery of the shown pull request (kept while reloading).
    public func load(_ id: PullRequestID?) async {
        guard let id else {
            loadState = .idle
            return
        }
        if deliveries[id] == nil { loadState = .loading }
        do {
            try await reload(id)
            guard !Task.isCancelled else { return }
            loadState = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            if deliveries[id] == nil { loadState = .failed(String(describing: error)) }
        }
    }

    /// Reloads the shown delivery every `interval` until the task is cancelled.
    public func keepRefreshing(_ id: PullRequestID?, every interval: Duration = refreshInterval) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled, let id else { return }
            // Followed deliveries are reloaded by the follower; finished ones don't change any more.
            if !isFollowing(id), deliveries[id]?.isFinished() != true { await load(id) }
        }
    }

    /// Loads once; a changed answer replaces the shown delivery and, when followed, raises its events.
    private func reload(_ id: PullRequestID, now: Date = .now) async throws {
        let loaded = try await loader.loadDelivery(for: id)
        let old = deliveries[id]
        if old != loaded { deliveries[id] = loaded }
        guard let loaded, isFollowing(id) else { return }
        for event in DeliveryEvent.changes(from: old, to: loaded) { onEvent?(event) }
        scheduleVerifications(from: old, to: loaded, now: now)
    }

    // MARK: Following

    public func isFollowing(_ id: PullRequestID) -> Bool { followed.contains(id) }

    /// Follows a delivery in the background: an event per stage until it is through.
    public func follow(_ id: PullRequestID) {
        guard !followed.contains(id) else { return }
        followed.append(id)
        saveFollowed()
    }

    public func unfollow(_ id: PullRequestID) {
        followed.removeAll { $0 == id }
        settledSince[id] = nil
        scheduled.removeAll { $0.pullRequest == id }
        saveFollowed()
    }

    /// Reloads the followed deliveries every `interval` until the task is cancelled (run once by the app).
    public func keepFollowing(every interval: Duration = refreshInterval) async {
        while !Task.isCancelled {
            await refreshFollowed()
            try? await Task.sleep(for: interval)
        }
    }

    /// One round of the follower: reload, raise events, and stop following what is through.
    func refreshFollowed(now: Date = .now) async {
        for id in followed {
            do {
                try await reload(id, now: now)
            } catch {
                Self.logger.error(
                    "Following \(id.description, privacy: .public) failed: \(String(describing: error), privacy: .public)"
                )
                continue
            }
            // Not merged (yet), e.g. auto-merge still waiting: keep following.
            guard let delivery = deliveries[id] else { continue }
            await runDueVerifications(for: id, now: now)
            guard delivery.isFinished(at: now) else {
                settledSince[id] = nil
                if now.timeIntervalSince(delivery.mergedAt ?? now) > Self.followLimit { unfollow(id) }
                continue
            }
            let since = settledSince[id] ?? now
            settledSince[id] = since
            // A delivery that ends in a failure or without any stage is over at once.
            let isOver = delivery.stages.isEmpty || delivery.overallState(at: now) == .failed
            // A verification still to come keeps the delivery followed.
            guard !scheduled.contains(where: { $0.pullRequest == id }) else { continue }
            guard isOver || now.timeIntervalSince(since) >= Self.settleTime else { continue }
            unfollow(id)
            let kind: DeliveryEvent.Kind = delivery.stages.isEmpty ? .nothingStarted : .complete
            // The failed stage was reported already.
            if delivery.overallState(at: now) != .failed {
                onEvent?(DeliveryEvent(pullRequest: id, title: delivery.title, kind: kind))
            }
        }
    }

    private func saveFollowed() {
        defaults?.set(followed.map(\.description), forKey: Self.followedKey)
    }

    // MARK: Stages and approval

    /// The stage whose card is shown: the selected one, else the delivery's current stage.
    public func shownStage(for id: PullRequestID) -> DeliveryStage? {
        guard let delivery = deliveries[id] else { return nil }
        return delivery.stages.first { $0.id == selectedStage[id] } ?? delivery.currentStage
    }

    /// Approves a waiting deployment on GitHub (the user's click, confirmed in the view).
    public func approve(_ stage: DeliveryStage, of id: PullRequestID) async {
        guard let approval = stage.approval, approval.viewerCanApprove, !isApproving else { return }
        isApproving = true
        approvalError = nil
        defer { isApproving = false }
        do {
            try await loader.approve(approval)
        } catch {
            approvalError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            return
        }
        await load(id)
    }
}
