import Foundation
import Observation
import Platform
import SylvraCore

/// State of AI reviews: settings, running jobs and results per pull request.
@MainActor
@Observable
public final class AIReviewModel {
    public enum Tab: String, CaseIterable, Identifiable {
        case findings, patterns, chat, summary
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
    public private(set) var runState: RunState = .idle
    public private(set) var runningPullRequest: PullRequestID?
    public private(set) var agentVersion: String?
    /// Set when the checkout for repository context failed — the review then only sees the diff.
    public private(set) var workspaceWarning: String?
    private var runTask: Task<Void, Never>?
    public var selectedFindingID: UUID?
    public var tab: Tab = .findings
    public private(set) var dismissed: Set<UUID> = []
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
        let task = Task { await perform(id, title: title, body: body) }
        runTask = task
        await task.value
        runTask = nil
    }

    /// Stops a running review; agent processes are terminated.
    public func cancel() {
        runTask?.cancel()
    }

    private func perform(_ id: PullRequestID, title: String, body: String) async {
        do {
            async let filesToReview = files(id)
            async let checkout = workspace(id)
            let reviewable = try await filesToReview
            var directory: URL?
            do {
                directory = try await checkout
            } catch {
                workspaceWarning = String(
                    localized: "Reviewing the diff only — checkout failed: \(error.localizedDescription)")
            }
            let root = directory
            let context = await Task.detached { root.map { RepoContextDiscovery().documents(in: $0) } ?? [] }.value
            let input = ReviewEngine.Input(
                files: reviewable, title: title, body: body, context: context, history: [], settings: settings(for: id),
                workingDirectory: directory)
            let result = await engine.run(input) { [weak self] update in
                self?.apply(update)
            }
            if Task.isCancelled {
                runState = .failed(String(localized: "Cancelled"))
                return
            }
            results[id] = result
            cache?.save(
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
        selectedFindingID = finding.id
        tab = .findings
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
