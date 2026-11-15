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
    public var lineHighlights: [LineHighlight] = []

    /// The strongest highlight covering a new-side line.
    public func highlight(path: String, newLine: Int) -> LineHighlight? {
        lineHighlights.filter { $0.path == path && $0.lines.contains(newLine) }
            .max { ($0.isSelected ? 2 : $0.intensity) < ($1.isSelected ? 2 : $1.intensity) }
    }

    private let loader: any DiffLoading
    private var pullRequestID: PullRequestID?
    private var headSHA: String?

    public init(loader: any DiffLoading) {
        self.loader = loader
    }

    public var files: [FileDiff] { diff?.files ?? [] }

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
            loadState = .loading
        }
        pullRequestID = id
        self.headSHA = headSHA
        do {
            let loaded = try await loader.loadDiff(for: id)
            guard !Task.isCancelled else { return }
            diff = loaded
            loadState = .loaded
            if scope == .fullFile { await loadFullFiles() }
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
        do {
            try await loader.setViewed(viewed, path: path, pullRequestNodeID: nodeID)
        } catch {
            // Roll back on failure.
            if viewed { self.diff?.viewedPaths.remove(path) } else { self.diff?.viewedPaths.insert(path) }
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
    }

    private func loadFullFiles() async {
        guard let pullRequestID, let headSHA else { return }
        for file in files where fullFileHunks[file.path] == nil && file.status != .deleted && !file.isBinary {
            guard let content = try? await loader.loadFileContent(for: pullRequestID, path: file.path, ref: headSHA),
                !content.isEmpty
            else { continue }
            fullFileHunks[file.path] = FullFileBuilder.hunk(newContent: content, diff: file)
        }
    }
}
