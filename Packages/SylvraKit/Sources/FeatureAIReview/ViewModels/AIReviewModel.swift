import Foundation
import Observation
import Platform
import SylvraCore

/// State of AI reviews: settings, running jobs and results per pull request.
@MainActor
@Observable
public final class AIReviewModel {
    public enum Tab: String, CaseIterable, Identifiable {
        case findings, patterns, chat
        public var id: String { rawValue }
    }

    public enum RunState: Equatable {
        case idle, running, done, failed(String)
    }

    /// Supplies the files to review (diff) for a PR — provided by the app.
    public typealias FilesProvider = @Sendable (PullRequestID) async throws -> [ReviewableFile]
    /// Prepares a checkout the agent may read — provided by the app; `nil` = no checkout.
    public typealias WorkspaceProvider = @Sendable (PullRequestID) async throws -> URL?

    public private(set) var results: [PullRequestID: ReviewResult] = [:]
    public private(set) var progress: [ReviewEngine.Progress] = []
    /// What the review prepares before its agents start (loading the diff, checking out, reading guidelines);
    /// `nil` once the agents run. Without it the inspector showed only *Cancel* for that time.
    public private(set) var preparation: String?
    public private(set) var runState: RunState = .idle
    public private(set) var runningPullRequest: PullRequestID?
    public private(set) var agentVersion: String?
    /// Set when the checkout for repository context failed — the review then only sees the diff.
    public private(set) var workspaceWarning: String?
    private var runTask: Task<Void, Never>?
    public var selectedFindingID: UUID?
    public var tab: Tab = .findings
    /// Changes with every `showFinding` so the inspector scrolls to it, also when it's already selected.
    public private(set) var findingRequest = UUID()

    /// Selects a finding and asks the inspector to show it (e.g. its highlight was clicked in the diff).
    public func showFinding(_ id: UUID) {
        selectedFindingID = id
        tab = .findings
        findingRequest = UUID()
    }

    /// The pattern whose evidence is marked in the diff (also clicked there).
    public var selectedPatternID: String?

    /// Selects a pattern and shows it in the Patterns tab (e.g. its highlight was clicked in the diff).
    public func showPattern(_ id: String) {
        selectedPatternID = id
        selectedFindingID = nil
        tab = .patterns
        findingRequest = UUID()
    }
    public private(set) var dismissed: Set<UUID> = []
    /// The pull request's head commit right now (wired by the app), to tell whether a review is outdated.
    public var currentHeadSHA: @MainActor (PullRequestID) -> String? = { _ in nil }
    public var defaultSettings: ReviewSettings {
        didSet { save(defaultSettings, key: "aiReview.defaultSettings") }
    }

    public static let availableModels = ["opus", "fable", "sonnet", "haiku"]
    public static let efforts = ["low", "medium", "high", "xhigh", "max"]

    private let engine: ReviewEngine
    private let files: FilesProvider
    private let workspace: WorkspaceProvider
    private let defaults: UserDefaults
    private var overrides: [String: ReviewSettings]
    private let cache: JSONCache?

    public init(
        engine: ReviewEngine, files: @escaping FilesProvider, workspace: @escaping WorkspaceProvider,
        defaults: UserDefaults = .standard, cache: JSONCache? = nil
    ) {
        self.cache = cache
        if let saved = cache?.load([String: ReviewResult].self, key: "ai-review-results") {
            results = Dictionary(
                uniqueKeysWithValues: saved.compactMap { key, value in PullRequestID(key).map { ($0, value) } })
        }
        self.engine = engine
        self.files = files
        self.workspace = workspace
        self.defaults = defaults
        defaultSettings =
            Self.load(ReviewSettings.self, key: "aiReview.defaultSettings", from: defaults) ?? ReviewSettings()
        overrides = Self.load([String: ReviewSettings].self, key: "aiReview.overrides", from: defaults) ?? [:]
    }

    public var providerName: String { engine.providerName }

    // MARK: Settings (defaults + per-PR override)

    public func settings(for id: PullRequestID) -> ReviewSettings { overrides[id.description] ?? defaultSettings }

    public func setSettings(_ settings: ReviewSettings, for id: PullRequestID) {
        overrides[id.description] = settings
        save(overrides, key: "aiReview.overrides")
    }

    public func toggleModel(_ model: String, for id: PullRequestID) {
        var settings = settings(for: id)
        if settings.models.contains(model) {
            if settings.models.count > 1 { settings.models.removeAll { $0 == model } }
        } else {
            settings.models.append(model)
        }
        setSettings(settings, for: id)
    }

    // MARK: Running

    public func detectAgent() async {
        agentVersion = await engine.detectVersion()
    }

    public func run(_ id: PullRequestID, title: String, body: String) async {
        guard runState != .running else { return }
        runningPullRequest = id
        runState = .running
        progress = []
        workspaceWarning = nil
        tab = .findings
        // A new run starts from scratch: old findings (and their diff highlights) go away right away and
        // only come back if the run fails or is cancelled.
        let previous = results.removeValue(forKey: id)
        selectedFindingID = nil
        let task = Task { await perform(id, title: title, body: body) }
        runTask = task
        await task.value
        // A replacing run may have started meanwhile (see `replaceRunningReview`).
        if runTask == task { runTask = nil }
        if results[id] == nil, let previous, runState != .done { results[id] = previous }
    }

    /// Stops a running review; agent processes are terminated.
    public func cancel() {
        runTask?.cancel()
    }

    /// Stops the review running for another pull request and reviews `id` instead (one review at a time).
    public func replaceRunningReview(with id: PullRequestID, title: String, body: String) async {
        let running = runTask
        cancel()
        await running?.value
        await run(id, title: title, body: body)
    }

    /// Agents of the running review that finished (done or failed), for the activity overview.
    public var finishedAgentCount: Int {
        progress.count { $0.state != .queued && $0.state != .running }
    }

    private func perform(_ id: PullRequestID, title: String, body: String) async {
        let headSHA = currentHeadSHA(id)
        defer { preparation = nil }
        do {
            preparation = String(localized: "Loading the diff…")
            async let filesToReview = files(id)
            async let checkout = workspace(id)
            let reviewable = try await filesToReview
            preparation = String(localized: "Checking out the pull request…")
            var directory: URL?
            do {
                directory = try await checkout
            } catch {
                workspaceWarning = String(
                    localized: "Reviewing the diff only — checkout failed: \(error.localizedDescription)")
            }
            preparation = String(localized: "Reading the project's guidelines…")
            let root = directory
            let context = await Task.detached { root.map { RepoContextDiscovery().documents(in: $0) } ?? [] }.value
            let input = ReviewEngine.Input(
                files: reviewable, title: title, body: body, context: context, history: [], settings: settings(for: id),
                workingDirectory: directory)
            preparation = nil
            let result = await engine.run(input) { [weak self] update in
                self?.apply(update)
            }
            if Task.isCancelled {
                runState = .failed(String(localized: "Cancelled"))
                return
            }
            var reviewed = result
            reviewed.headSHA = headSHA
            reviewed.reviewedAt = .now
            results[id] = reviewed
            cache?.saveInBackground(
                Dictionary(uniqueKeysWithValues: results.map { ($0.key.description, $0.value) }),
                key: "ai-review-results")
            let failures = progress.filter { if case .failed = $0.state { true } else { false } }
            runState =
                failures.count == progress.count && !progress.isEmpty ? .failed(Self.failureText(failures)) : .done
        } catch {
            runState = .failed(error.localizedDescription)
        }
    }

    private func apply(_ update: ReviewEngine.Progress) {
        if let index = progress.firstIndex(where: { $0.id == update.id }) {
            progress[index] = update
        } else {
            progress.append(update)
        }
    }

    /// The pull request got new commits since its last review (a run again sees the current diff).
    public func isOutdated(_ id: PullRequestID?) -> Bool {
        guard let id, let reviewed = results[id]?.headSHA, let current = currentHeadSHA(id) else { return false }
        return reviewed != current
    }

    // MARK: Findings

    public func visibleFindings(for id: PullRequestID?) -> [ReviewFinding] {
        guard let id else { return [] }
        return (results[id]?.findings ?? []).filter { !dismissed.contains($0.id) }
    }

    /// Selects the next / previous finding (`J` / `K`) and returns it.
    @discardableResult
    public func selectFinding(offset: Int, for id: PullRequestID?) -> ReviewFinding? {
        let findings = visibleFindings(for: id)
        guard !findings.isEmpty else { return nil }
        let current = findings.firstIndex { $0.id == selectedFindingID } ?? (offset > 0 ? -1 : findings.count)
        let finding = findings[min(max(current + offset, 0), findings.count - 1)]
        showFinding(finding.id)
        return finding
    }

    public func dismiss(_ finding: ReviewFinding) {
        dismissed.insert(finding.id)
        if selectedFindingID == finding.id { selectedFindingID = nil }
    }

    /// Anchored, not dismissed findings (for diff highlights).
    public func findings(for id: PullRequestID?) -> [ReviewFinding] {
        visibleFindings(for: id).filter(\.isAnchored)
    }

    public func findings(in path: String, for id: PullRequestID?) -> [ReviewFinding] {
        visibleFindings(for: id).filter { $0.path == path && $0.isAnchored }
    }

    /// Puts a result in place (tests).
    func restoreForTesting(_ result: ReviewResult?, for id: PullRequestID) { results[id] = result }

    // MARK: Persistence helpers

    private func save(_ value: some Encodable, key: String) {
        defaults.set(try? JSONEncoder().encode(value), forKey: key)
    }

    private static func load<Value: Decodable>(_ type: Value.Type, key: String, from defaults: UserDefaults) -> Value? {
        defaults.data(forKey: key).flatMap { try? JSONDecoder().decode(type, from: $0) }
    }

    private static func failureText(_ failures: [ReviewEngine.Progress]) -> String {
        failures.compactMap { if case .failed(let message) = $0.state { message } else { nil } }.first ?? ""
    }
}

extension ReviewEngine {
    func detectVersion() async -> String? { await providerVersion() }
}
