import Foundation
import Observation
import SylvraCore

/// State of the diff view and the file navigator.
@MainActor
@Observable
public final class DiffScreenModel {
    public enum Layout: String, CaseIterable, Identifiable {
        case sideBySide, inline
        public var id: String { rawValue }
    }

    public enum Scope: String, CaseIterable, Identifiable {
        case focused, fullFile
        /// Only what changed since the reviewer's last review (last reviewed commit → head).
        case sinceLastReview
        public var id: String { rawValue }
    }

    public enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    public private(set) var diff: PullRequestDiff?
    public private(set) var loadState: LoadState = .idle
    public var layout: Layout = .sideBySide
    public var scope: Scope = .focused
    /// File the reviewer jumped to (from the navigator).
    public var selectedPath: String?
    /// Files the reviewer expanded although they are collapsed by default (viewed / noise).
    public private(set) var expandedPaths: Set<String> = []
    public private(set) var fullFileHunks: [String: Hunk] = [:]
    /// AI highlights, set by the app from findings.
    public var lineHighlights: [LineHighlight] = [] {
        didSet { highlightIndex = Dictionary(grouping: lineHighlights, by: \.path) }
    }
    private var highlightIndex: [String: [LineHighlight]] = [:]
    /// Called with a finding ID when the reviewer clicks its highlight in the diff (set by the app).
    @ObservationIgnored public var selectFinding: ((String) -> Void)?
    /// Last error of a background action (viewed sync, full-file loading), shown as a banner.
    public var lastError: String?

    /// The strongest highlight covering a new-side line.
    public func highlight(path: String, newLine: Int) -> LineHighlight? {
        (highlightIndex[path] ?? []).filter { $0.lines.contains(newLine) }
            .max { ($0.isSelected ? 2 : $0.intensity) < ($1.isSelected ? 2 : $1.intensity) }
    }

    let loader: any DiffLoading
    var pullRequestID: PullRequestID?
    var headSHA: String?

    public init(loader: any DiffLoading, pollInterval: Duration = .seconds(60)) {
        self.loader = loader
        self.pollInterval = pollInterval
    }

    public var files: [FileDiff] {
        if selectedCommit != nil { return commitFiles ?? [] }
        return scope == .sinceLastReview ? (sinceReviewFiles ?? []) : (diff?.files ?? [])
    }

    // MARK: - Commit by commit

    /// The PR's commits, oldest first (set by the app from the PR details).
    public var commits: [Commit] = []
    /// The commit shown on its own; `nil` shows all changes of the PR.
    public internal(set) var selectedCommit: Commit?
    /// Files changed by `selectedCommit`.
    public internal(set) var commitFiles: [FileDiff]?
    public internal(set) var isLoadingCommit = false

    // MARK: - Since last review / new pushes

    /// Head and last reviewed commit, refreshed when loading and while polling.
    public internal(set) var progress: ReviewProgress?
    /// Files changed between the last reviewed commit and head (scope `.sinceLastReview`).
    public internal(set) var sinceReviewFiles: [FileDiff]?
    /// Someone pushed after the diff was loaded.
    public internal(set) var hasNewCommits = false
    /// How often to check for new pushes.
    public let pollInterval: Duration

    /// AI-suggested reading order, set by the app from the review result.
    public var readingOrder: [ReadingStep] = []
    /// Sort the diff by `readingOrder` (else repository order).
    public var usesReadingOrder = true

    /// Position (1-based) and step of a file in the reading order.
    public func readingStep(for path: String) -> (number: Int, step: ReadingStep)? {
        guard let index = readingOrder.firstIndex(where: { $0.path == path }) else { return nil }
        return (index + 1, readingOrder[index])
    }

    /// Files ordered for reviewing: AI reading order (if any and enabled), the rest, noise last.
    public var orderedFiles: [FileDiff] {
        var relevant = files.filter { !$0.kind.isNoise }
        if usesReadingOrder, !readingOrder.isEmpty {
            let rank = Dictionary(
                readingOrder.enumerated().map { ($1.path, $0) }, uniquingKeysWith: { first, _ in first })
            let original = Dictionary(
                relevant.enumerated().map { ($1.path, $0) }, uniquingKeysWith: { first, _ in first })
            relevant.sort {
                (rank[$0.path] ?? Int.max, original[$0.path] ?? 0) < (rank[$1.path] ?? Int.max, original[$1.path] ?? 0)
            }
        }
        return relevant + files.filter(\.kind.isNoise)
    }

    public var viewedCount: Int { files.count { isViewed($0.path) } }

    public func isViewed(_ path: String) -> Bool { diff?.viewedPaths.contains(path) ?? false }

    /// Viewed files and noise are collapsed unless the reviewer opens them.
    public func isCollapsed(_ file: FileDiff) -> Bool {
        (isViewed(file.path) || file.kind.isNoise || file.isBinary) && !expandedPaths.contains(file.path)
    }

    /// Moves the selection to the next / previous file in review order (`]` / `[`).
    public func selectFile(offset: Int) {
        let paths = orderedFiles.map(\.path)
        guard !paths.isEmpty else { return }
        let current = selectedPath.flatMap(paths.firstIndex(of:)) ?? (offset > 0 ? -1 : paths.count)
        selectedPath = paths[min(max(current + offset, 0), paths.count - 1)]
    }

    /// A line the diff should scroll to (new side), e.g. an AI finding; reset after scrolling.
    public private(set) var focusedLine: FocusedLine?

    /// How far the code is scrolled sideways (all rows together; gutters stay put).
    public var horizontalOffset: CGFloat = 0
    /// Longest shown line, cached per diff state (scrolling re-renders often).
    @ObservationIgnored var longestLineCache: (key: Int, length: Int)?

    /// A scroll request to a new-side line; `token` makes repeated requests for the same line distinct.
    public struct FocusedLine: Equatable, Sendable {
        public let path: String
        public let line: Int
        public let token = UUID()
    }

    /// Scrolls to a line of the new version and expands its file if it is collapsed. A line the diff doesn't
    /// show (e.g. an AI finding on unchanged code) snaps to the nearest shown line, so the jump still lands.
    public func focus(path: String, line: Int) {
        var target = line
        if let file = files.first(where: { $0.path == path }) {
            if isCollapsed(file) { toggleExpanded(path) }
            target = Self.nearestShownLine(to: line, in: hunks(for: file)) ?? line
        }
        selectedPath = path
        focusedLine = FocusedLine(path: path, line: target)
    }

    // MARK: - Change navigation and find

    /// A block of changed lines to jump to (new-side line of its first visible row).
    public struct ChangeTarget: Equatable, Sendable {
        public let path: String
        public let line: Int
    }

    var lastChange: ChangeTarget?

    public var isSearchPresented = false
    public var searchQuery = "" {
        didSet { currentSearchMatch = nil }
    }
    /// The match the reviewer jumped to last.
    public internal(set) var currentSearchMatch: ChangeTarget?

    /// Scroll anchor ID of a new-side line.
    public nonisolated static func lineAnchor(path: String, line: Int) -> String { "\(path)#L\(line)" }

    /// Folders the reviewer collapsed in the file tree.
    public internal(set) var collapsedFolders: Set<String> = []

    public func toggleFolder(_ path: String) {
        if collapsedFolders.contains(path) { collapsedFolders.remove(path) } else { collapsedFolders.insert(path) }
    }

    /// Bumped when the navigator should bring `selectedPath` into view (a click on a file header in the diff).
    public internal(set) var navigatorRevealToken = 0
    /// The next `selectedPath` change came from the diff itself: the diff keeps its scroll position.
    @ObservationIgnored var keepsDiffPosition = false
    /// Brings a file's header to the top of the diff, also when the file is already selected (`id` makes each
    /// request a change).
    public internal(set) var headerRequest: (path: String, id: UUID)?

    /// Changed files as a folder tree (noise last).
    public var fileTree: [FileTreeNode] {
        let tree = FileTreeNode.build(files.filter { !$0.kind.isNoise })
        let noise = files.filter(\.kind.isNoise)
        return noise.isEmpty
            ? tree
            : tree + [
                FileTreeNode(
                    path: "#noise", name: String(localized: "Generated & lockfiles"),
                    file: nil, children: FileTreeNode.build(noise))
            ]
    }

    public func toggleExpanded(_ path: String) {
        if expandedPaths.contains(path) { expandedPaths.remove(path) } else { expandedPaths.insert(path) }
    }

    /// Hunks to show for a file in the current scope (with context the reviewer revealed).
    public func hunks(for file: FileDiff) -> [Hunk] {
        // Full files and revealed context come from head; a single commit's lines may differ.
        if selectedCommit != nil { return file.hunks }
        if scope == .fullFile, let full = fullFileHunks[file.path] { return [full] }
        guard let revealed = revealedContext[file.path], let lines = headLines[file.path] else { return file.hunks }
        return ContextExpander.expand(file.hunks, revealed: revealed, headLines: lines)
    }

    // MARK: - Context expansion

    /// Context lines revealed above each hunk, per file.
    public internal(set) var revealedContext: [String: [Int: Int]] = [:]
    /// File contents at head, loaded on the first expansion.
    var headLines: [String: [String]] = [:]

    /// Text of the lines at a location (joined with newlines), used to pre-fill code suggestions.
    public func text(at location: CodeLocation) -> String {
        guard let file = files.first(where: { $0.path == location.path }) else { return "" }
        let lines = (hunks(for: file) + file.hunks).lazy.flatMap(\.lines)
        return location.lines.compactMap { number in
            lines.first { line in
                switch location.side {
                case .left: line.kind != .added && line.oldNumber == number
                case .right: line.kind != .removed && line.newNumber == number
                }
            }?.text
        }
        .joined(separator: "\n")
    }

    public func load(_ id: PullRequestID?, headSHA: String?) async {
        guard let id else {
            diff = nil
            loadState = .idle
            return
        }
        if pullRequestID != id {
            diff = nil
            expandedPaths = []
            fullFileHunks = [:]
            selectedPath = nil
            progress = nil
            sinceReviewFiles = nil
            revealedContext = [:]
            headLines = [:]
            selectedCommit = nil
            commitFiles = nil
            horizontalOffset = 0
            if scope == .sinceLastReview { scope = .focused }
            loadState = .loading
        }
        pullRequestID = id
        self.headSHA = headSHA
        do {
            let loaded = try await loader.loadDiff(for: id)
            guard !Task.isCancelled else { return }
            // A reload with the same diff (e.g. a refresh) must not re-render it.
            if diff != loaded { diff = loaded }
            if loadState != .loaded { loadState = .loaded }
            await loadProgress(id)
            if scope == .fullFile { await loadFullFiles() }
            if scope == .sinceLastReview { await loadSinceReview() }
        } catch {
            guard !Task.isCancelled else { return }
            loadState = .failed(String(describing: error))
        }
    }

    /// Toggles the viewed state locally (optimistic) and on GitHub.
    public func toggleViewed(_ path: String) async {
        guard var diff else { return }
        let viewed = !diff.viewedPaths.contains(path)
        if viewed { diff.viewedPaths.insert(path) } else { diff.viewedPaths.remove(path) }
        expandedPaths.remove(path)
        self.diff = diff
        guard let nodeID = diff.nodeID else { return }
        let pullRequest = pullRequestID
        do {
            try await loader.setViewed(viewed, path: path, pullRequestNodeID: nodeID)
        } catch {
            // Roll back on failure — only if the same PR is still shown.
            guard pullRequestID == pullRequest else { return }
            if viewed { self.diff?.viewedPaths.remove(path) } else { self.diff?.viewedPaths.insert(path) }
            lastError = String(localized: "Couldn't update “viewed” on GitHub: \(error.localizedDescription)")
        }
    }

    /// Marks all files below a folder as viewed / not viewed.
    public func setViewed(_ viewed: Bool, folder: String) async {
        let prefix = folder.isEmpty ? "" : folder + "/"
        for file in files where file.path.hasPrefix(prefix) && isViewed(file.path) != viewed {
            await toggleViewed(file.path)
        }
    }

    public func setScope(_ scope: Scope) async {
        self.scope = scope
        if scope == .fullFile { await loadFullFiles() }
        if scope == .sinceLastReview, sinceReviewFiles == nil { await loadSinceReview() }
    }

    /// Loads the head version of every changed file, a few at a time.
    ///
    /// Plain child tasks instead of a task group: the app crashed in `TaskGroup.offer` when the scope was
    /// switched while files were loading (a group finishing children after its parent moved on).
    private func loadFullFiles() async {
        guard let pullRequestID, let headSHA else { return }
        let id = pullRequestID
        let loader = loader
        let pending = files.filter { fullFileHunks[$0.path] == nil && $0.status != .deleted && !$0.isBinary }
        for start in stride(from: 0, to: pending.count, by: Self.fullFileBatchSize) {
            let batch = Array(pending[start..<min(start + Self.fullFileBatchSize, pending.count)])
            let tasks = batch.map { file in
                Task.detached { () -> Result<String, any Error> in
                    do {
                        return .success(try await loader.loadFileContent(for: id, path: file.path, ref: headSHA))
                    } catch {
                        return .failure(error)
                    }
                }
            }
            var results: [Result<String, any Error>] = []
            await withTaskCancellationHandler {
                for task in tasks { results.append(await task.value) }
            } onCancel: {
                for task in tasks { task.cancel() }
            }
            // Drop results of a PR the reviewer already left.
            guard !Task.isCancelled, self.pullRequestID == id else { return }
            for (file, result) in zip(batch, results) where fullFileHunks[file.path] == nil {
                switch result {
                case .success(let content) where !content.isEmpty:
                    fullFileHunks[file.path] = FullFileBuilder.hunk(newContent: content, diff: file)
                case .failure(let error) where !(error is CancellationError):
                    lastError = String(localized: "Couldn't load \(file.fileName): \(error.localizedDescription)")
                default:
                    break
                }
            }
        }
    }

    /// Files loaded in parallel for full-file view (large PRs would otherwise fire hundreds of requests).
    static let fullFileBatchSize = 8
}
