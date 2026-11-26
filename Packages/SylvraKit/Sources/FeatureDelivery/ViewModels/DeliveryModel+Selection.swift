import Foundation
import SylvraCore

/// What the details of the selected stage show.
public enum DeliveryItem: Hashable, Sendable {
    /// A job and its log.
    case job(String)
    /// A check of the AI check, by its title.
    case check(String)
    /// What the AI check could not check.
    case notChecked
    /// What the agent did during the AI check.
    case activity
}

extension DeliveryItem {
    /// Part of a stage's AI check (not a job).
    public var isAICheck: Bool {
        if case .job = self { return false }
        return true
    }
}

/// One column of the AI check band: a stage's check — its result, running, or still to do.
public struct AICheckColumn: Equatable, Sendable, Identifiable {
    public let stage: DeliveryStage
    public let result: StageVerification?
    public let isRunning: Bool
    public let error: String?
    public let isCheckable: Bool

    public var id: String { stage.id }

    /// The boxes of the column: the checks, or one box for the whole column (running, to do, failed).
    public var boxIDs: [String] {
        guard let result, !result.checks.isEmpty, !isRunning else { return ["ai#\(stage.id)#check"] }
        return result.checks.map { "ai#\(stage.id)#\($0.title)" }
    }
}

/// A job log being loaded or shown.
public enum LogState: Equatable, Sendable {
    case loading
    case loaded(JobLog)
    case failed(String)
}

extension DeliveryModel {
    /// The delivery in short for the inbox (`nil`: none known).
    public func badge(for id: PullRequestID) -> DeliveryBadge? {
        guard let delivery = deliveries[id] else { return nil }
        return delivery.badge(verdicts: (verifications[id] ?? [:]).mapValues(\.verdict))
    }

    /// The main area shows the delivery: the pull request is merged and the user didn't switch to the diff.
    public func showsDelivery(_ id: PullRequestID?, isMerged: Bool) -> Bool {
        guard let id, isMerged else { return false }
        return !showsDiff.contains(id)
    }

    public func setShowsDelivery(_ shows: Bool, for id: PullRequestID) {
        if shows { showsDiff.remove(id) } else { showsDiff.insert(id) }
    }

    /// Marks a selection in the AI check band: `ai#<stage id>`.
    public static let aiPrefix = "ai#"

    /// The details show a stage's AI check (its column in the AI check band is selected).
    public func isShowingAICheck(for id: PullRequestID) -> Bool {
        selectedStage[id]?.hasPrefix(Self.aiPrefix) == true
    }

    /// Selects a stage's AI check, optionally one of its checks.
    public func selectAICheck(_ stageID: String, item: DeliveryItem? = nil, of id: PullRequestID) {
        selectedStage[id] = Self.aiPrefix + stageID
        selectedItem[id] = item
    }

    /// The columns of the AI check band, one per stage that can be checked (a deployed environment or a failed
    /// stage) or was checked; empty without an agent and without results.
    public func aiColumns(for id: PullRequestID) -> [AICheckColumn] {
        guard let delivery = deliveries[id] else { return [] }
        return delivery.stages.compactMap { stage -> AICheckColumn? in
            let result = verification(of: stage, in: id)
            let isCheckable = stage.state == .failed || (stage.state == .succeeded && stage.kind == .environment)
            guard (isCheckable && canVerify) || result != nil else { return nil }
            return AICheckColumn(
                stage: stage, result: result, isRunning: isVerifying(stage, in: id),
                error: verificationError(of: stage, in: id), isCheckable: isCheckable && canVerify)
        }
    }

    /// Selects a stage; its details start with what matters most.
    public func selectStage(_ stageID: String, of id: PullRequestID) {
        selectedStage[id] = stageID
        selectedItem[id] = nil
    }

    /// Selects a job (a click on its box in the graph): its stage, and its log in the details.
    public func selectJob(_ jobID: String, of id: PullRequestID) {
        guard let stage = deliveries[id]?.stages.first(where: { $0.jobs.contains { $0.id == jobID } }) else { return }
        selectedStage[id] = stage.id
        select(.job(jobID), of: id)
    }

    /// Shows an item in the details; a job's log is loaded on the way.
    public func select(_ item: DeliveryItem, of id: PullRequestID) {
        selectedItem[id] = item
        if case .job(let jobID) = item, let job = shownStage(for: id)?.jobs.first(where: { $0.id == jobID }),
            let number = job.jobID, needsLog(number, running: job.state == .running)
        {
            Task { await loadLog(number, of: id) }
        }
    }

    /// A log is loaded once, again after a failure, and every time for a job that still runs.
    private func needsLog(_ number: Int, running: Bool) -> Bool {
        switch logs[number] {
        case nil, .failed: true
        case .loading: false
        case .loaded: running
        }
    }

    /// The item the details show: the selected one, else a failed job, a check with a problem, the first check,
    /// the first job.
    public func shownItem(for id: PullRequestID) -> DeliveryItem? {
        guard let stage = shownStage(for: id) else { return nil }
        let result = verification(of: stage, in: id)
        let isAI = isShowingAICheck(for: id)
        if let item = selectedItem[id], isValid(item, stage: stage, result: result), item.isAICheck == isAI {
            return item
        }
        if isAI {
            if let problem = result?.checks.first(where: { $0.outcome == .problem }) { return .check(problem.title) }
            return result?.checks.first.map { .check($0.title) }
        }
        if let failed = stage.jobs.first(where: { $0.state == .failed }) { return .job(failed.id) }
        if let running = stage.jobs.first(where: { $0.state == .running }) { return .job(running.id) }
        return stage.jobs.last.map { .job($0.id) }
    }

    private func isValid(_ item: DeliveryItem, stage: DeliveryStage, result: StageVerification?) -> Bool {
        switch item {
        case .job(let jobID): stage.jobs.contains { $0.id == jobID }
        case .check(let title): result?.checks.contains { $0.title == title } == true
        case .notChecked: result?.notChecked.isEmpty == false
        case .activity: result?.activity.isEmpty == false
        }
    }

    /// Loads a job's log (again after a failure); a running job's log is reloaded on every call.
    public func loadLog(_ number: Int, of id: PullRequestID) async {
        if logs[number] == nil { logs[number] = .loading }
        do {
            let text = try await loader.loadLog(jobID: number, in: id)
            logs[number] = .loaded(JobLog(text: text))
        } catch {
            if case .loaded = logs[number] { return }
            logs[number] = .failed((error as? LocalizedError)?.errorDescription ?? String(describing: error))
        }
    }
}
