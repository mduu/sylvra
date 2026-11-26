import Foundation
import SylvraCore

/// A verification that is due later: a deployed stage is checked once it has settled.
struct ScheduledVerification: Equatable {
    let pullRequest: PullRequestID
    let stageID: String
    let dueAt: Date
    let isSecondLook: Bool
}

extension DeliveryModel {
    static let autoVerifyKey = "delivery.autoVerify"
    static let verificationsKey = "delivery-verifications"
    /// How long a deployed stage runs before it is checked (errors need a moment to show).
    public static let verificationDelay: TimeInterval = 300
    /// When production is looked at a second time.
    public static let secondLookDelay: TimeInterval = 1_800
    /// Verifications kept per pull request list (the newest pull requests).
    static let keptPullRequests = 40

    /// Whether stages can be verified at all (an agent is available).
    public var canVerify: Bool { verifier != nil }

    public static func verificationKey(_ id: PullRequestID, _ stageID: String) -> String { "\(id)|\(stageID)" }

    public func verification(of stage: DeliveryStage, in id: PullRequestID) -> StageVerification? {
        verifications[id]?[stage.id]
    }

    public func isVerifying(_ stage: DeliveryStage, in id: PullRequestID) -> Bool {
        verifying.contains(Self.verificationKey(id, stage.id))
    }

    public func verificationError(of stage: DeliveryStage, in id: PullRequestID) -> String? {
        verificationErrors[Self.verificationKey(id, stage.id)]
    }

    // MARK: Monitoring notes

    /// What the user noted about a repository's monitoring (service names, environments), passed to the agent.
    public func monitoringNotes(for id: PullRequestID) -> String {
        defaults?.string(forKey: Self.notesKey(id)) ?? ""
    }

    public func setMonitoringNotes(_ notes: String, for id: PullRequestID) {
        defaults?.set(notes.trimmingCharacters(in: .whitespacesAndNewlines), forKey: Self.notesKey(id))
    }

    static func notesKey(_ id: PullRequestID) -> String { "delivery.monitoring.\(id.owner)/\(id.repository)" }

    // MARK: Verifying

    /// Checks a stage with the agent (the user's click, or automatically for a followed delivery).
    public func verify(_ stageID: String, of id: PullRequestID, isSecondLook: Bool = false, now: Date = .now) async {
        let key = Self.verificationKey(id, stageID)
        guard let verifier, let delivery = deliveries[id],
            let stage = delivery.stages.first(where: { $0.id == stageID }),
            !verifying.contains(key)
        else { return }
        verifying.insert(key)
        verificationErrors[key] = nil
        defer { verifying.remove(key) }
        let info = await pullRequestInfo?(id)
        let request = VerificationRequest(
            pullRequest: id, title: info?.title ?? delivery.title, body: info?.body ?? "", delivery: delivery,
            stage: stage, monitoringNotes: monitoringNotes(for: id), isSecondLook: isSecondLook)
        do {
            let result = try await verifier.verify(request)
            verifications[id, default: [:]][stageID] = result
            saveVerifications()
            if isFollowing(id) {
                onEvent?(
                    DeliveryEvent(pullRequest: id, title: delivery.title, kind: .verified(stage.name, result.verdict)))
            }
        } catch is CancellationError {
            return
        } catch {
            guard !Task.isCancelled else { return }
            verificationErrors[key] =
                (error as? LocalizedError)?.errorDescription
                ?? (error as NSError).userInfo[NSLocalizedDescriptionKey] as? String ?? String(describing: error)
        }
    }

    /// Starts a check from the view (*Check with AI*); `stopVerifying` ends it.
    public func startVerifying(_ stageID: String, of id: PullRequestID) {
        let key = Self.verificationKey(id, stageID)
        guard verificationTasks[key] == nil else { return }
        verificationTasks[key] = Task {
            await verify(stageID, of: id)
            verificationTasks[key] = nil
        }
    }

    /// Stops a running check: the agent process is terminated, the earlier result (if any) stays.
    public func stopVerifying(_ stageID: String, of id: PullRequestID) {
        let key = Self.verificationKey(id, stageID)
        verificationTasks.removeValue(forKey: key)?.cancel()
    }

    // MARK: Automatic verification of followed deliveries

    /// Plans the checks for stages that just finished: a deployed environment after the settling time (and
    /// production once more later), a failed stage at once.
    func scheduleVerifications(from old: Delivery?, to new: Delivery, now: Date) {
        guard verifiesAutomatically, canVerify, let old else { return }
        let before = Dictionary(old.stages.map { ($0.id, $0.state) }, uniquingKeysWith: { first, _ in first })
        for stage in new.stages where before[stage.id] != stage.state {
            switch stage.state {
            case .failed:
                schedule(new.pullRequest, stage.id, at: now, isSecondLook: false)
            case .succeeded where stage.kind == .environment:
                schedule(new.pullRequest, stage.id, at: now + Self.verificationDelay, isSecondLook: false)
                if stage.id == new.productionStage?.id {
                    schedule(new.pullRequest, stage.id, at: now + Self.secondLookDelay, isSecondLook: true)
                }
            default: break
            }
        }
    }

    private func schedule(_ id: PullRequestID, _ stageID: String, at date: Date, isSecondLook: Bool) {
        let entry = ScheduledVerification(pullRequest: id, stageID: stageID, dueAt: date, isSecondLook: isSecondLook)
        guard
            !scheduled.contains(where: {
                $0.stageID == stageID && $0.pullRequest == id && $0.isSecondLook == isSecondLook
            })
        else { return }
        scheduled.append(entry)
    }

    /// Runs what is due for a pull request, one after the other.
    func runDueVerifications(for id: PullRequestID, now: Date) async {
        let due = scheduled.filter { $0.pullRequest == id && $0.dueAt <= now }
        scheduled.removeAll { due.contains($0) }
        for entry in due {
            await verify(entry.stageID, of: id, isSecondLook: entry.isSecondLook, now: now)
        }
    }

    private func saveVerifications() {
        // Only the latest pull requests are kept.
        let newest = verifications.sorted { lhs, rhs in
            (lhs.value.values.map(\.checkedAt).max() ?? .distantPast)
                > (rhs.value.values.map(\.checkedAt).max() ?? .distantPast)
        }.prefix(Self.keptPullRequests)
        cache?.saveInBackground(
            Dictionary(uniqueKeysWithValues: newest.map { ($0.key.description, Array($0.value.values)) }),
            key: Self.verificationsKey)
    }
}
