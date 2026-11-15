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
    /// Last error of a background action (viewed sync, full-file loading), shown as a banner.
    public var lastError: String?

    /// The strongest highlight covering a new-side line.
    public func highlight(path: String, newLine: Int) -> LineHighlight? {
        (highlightIndex[path] ?? []).filter { $0.lines.contains(newLine) }
            .max { ($0.isSelected ? 2 : $0.intensity) < ($1.isSelected ? 2 : $1.intensity) }
    }

    private let loader: any DiffLoading
    private var pullRequestID: PullRequestID?
    private var headSHA: String?

    public init(loader: any DiffLoading, pollInterval: Duration = .seconds(60)) {
        self.loader = loader
        self.pollInterval = pollInterval
    }

    public var files: [FileDiff] {
        scope == .sinceLastReview ? (sinceReviewFiles ?? []) : (diff?.files ?? [])
    }

    // MARK: - Since last review / new pushes

    /// Head and last reviewed commit, refreshed when loading and while polling.
    public private(set) var progress: ReviewProgress?
    /// Files changed between the last reviewed commit and head (scope `.sinceLastReview`).
    public private(set) var sinceReviewFiles: [FileDiff]?
    /// Someone pushed after the diff was loaded.
    public private(set) var hasNewCommits = false
    /// How often to check for new pushes.
    public let pollInterval: Duration

    /// Checks GitHub for a new head commit (called periodically by the diff screen).
    public func checkForNewCommits() async {
        guard let id = pullRequestID, let loaded = progress,
            let latest = try? await loader.loadReviewProgress(for: id), pullRequestID == id
        else { return }
        if latest.headSHA != loaded.headSHA { hasNewCommits = true }
    }

    private func loadProgress(_ id: PullRequestID) async {
        guard let loaded = try? await loader.loadReviewProgress(for: id), pullRequestID == id else { return }
        progress = loaded
        hasNewCommits = false
    }

    private func loadSinceReview() async {
        guard let id = pullRequestID, let progress, let base = progress.lastReviewedSHA else {
            sinceReviewFiles = []
            return
        }
        do {
            let loaded = try await loader.loadDiff(for: id, from: base, to: progress.headSHA)
            guard pullRequestID == id else { return }
            sinceReviewFiles = loaded
        } catch {
            sinceReviewFiles = []
            let reason = error.localizedDescription
            lastError = String(
                localized: "Couldn't load the changes since your last review (gone after a force push?): \(reason)")
        }
    }

    /// Files ordered for reviewing: noise last.
    public var orderedFiles: [FileDiff] {
        files.filter { !$0.kind.isNoise } + files.filter(\.kind.isNoise)
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

    /// A scroll request to a new-side line; `token` makes repeated requests for the same line distinct.
    public struct FocusedLine: Equatable, Sendable {
        public let path: String
        public let line: Int
        public let token = UUID()
    }

    /// Scrolls to a line of the new version and expands its file if it is collapsed.
    public func focus(path: String, line: Int) {
        if let file = files.first(where: { $0.path == path }), isCollapsed(file) { toggleExpanded(path) }
        selectedPath = path
        focusedLine = FocusedLine(path: path, line: line)
    }

    /// Scroll anchor ID of a new-side line.
    public nonisolated static func lineAnchor(path: String, line: Int) -> String { "\(path)#L\(line)" }

    /// Folders the reviewer collapsed in the file tree.
    public private(set) var collapsedFolders: Set<String> = []

    public func toggleFolder(_ path: String) {
        if collapsedFolders.contains(path) { collapsedFolders.remove(path) } else { collapsedFolders.insert(path) }
    }

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

    /// Hunks to show for a file in the current scope.
    public func hunks(for file: FileDiff) -> [Hunk] {
        if scope == .fullFile, let full = fullFileHunks[file.path] { return [full] }
        return file.hunks
    }

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
            if scope == .sinceLastReview { scope = .focused }
            loadState = .loading
        }
        pullRequestID = id
        self.headSHA = headSHA
        do {
            let loaded = try await loader.loadDiff(for: id)
            guard !Task.isCancelled else { return }
            diff = loaded
            loadState = .loaded
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

    private func loadFullFiles() async {
        guard let pullRequestID, let headSHA else { return }
        let id = pullRequestID
        let loader = loader
        let pending = files.filter { fullFileHunks[$0.path] == nil && $0.status != .deleted && !$0.isBinary }
        await withTaskGroup(of: (String, Result<String, any Error>).self) { group in
            for file in pending {
                group.addTask {
                    do {
                        return (
                            file.path,
                            .success(try await loader.loadFileContent(for: id, path: file.path, ref: headSHA))
                        )
                    } catch {
                        return (file.path, .failure(error))
                    }
                }
            }
            for await (path, result) in group {
                // Drop results of a PR the reviewer already left.
                guard self.pullRequestID == id, let file = pending.first(where: { $0.path == path }) else { continue }
                switch result {
                case .success(let content) where !content.isEmpty:
                    fullFileHunks[path] = FullFileBuilder.hunk(newContent: content, diff: file)
                case .failure(let error):
                    lastError = String(localized: "Couldn't load \(file.fileName): \(error.localizedDescription)")
                default:
                    break
                }
            }
        }
    }
}
