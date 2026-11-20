import Foundation

/// Scope `.fullFile`: the selected file on its own, every line of its head version. (All files in full one
/// below the other was rarely useful and loaded and rendered every file of the pull request.)
extension DiffScreenModel {
    /// Only one file is in the diff: the selected one, in full.
    public var isShowingSingleFile: Bool { scope == .fullFile && selectedCommit == nil }

    /// The file shown in full: the selected file, else the first in review order.
    public var fullFilePath: String? {
        guard isShowingSingleFile else { return nil }
        if let selectedPath, files.contains(where: { $0.path == selectedPath }) { return selectedPath }
        return orderedFiles.first?.path
    }

    /// The files the diff shows, in review order.
    public var shownFiles: [FileDiff] {
        guard let path = fullFilePath else { return orderedFiles }
        return orderedFiles.filter { $0.path == path }
    }

    /// The file shown in full is still loading (its changed hunks are shown meanwhile).
    public var isLoadingFullFile: Bool { fullFilePath.map(loadingFullFiles.contains) ?? false }

    /// The diff waits for lines of the chosen scope (shown as a badge over the diff).
    public var isLoadingScope: Bool {
        isLoadingFullFile || (scope == .sinceLastReview && selectedCommit == nil && isLoadingSinceReview)
    }

    /// Loads the head version of the file shown in full (once per file and pull request).
    public func loadFullFile() async {
        guard let path = fullFilePath, fullFileHunks[path] == nil, let pullRequestID, let headSHA,
            let file = files.first(where: { $0.path == path }), file.status != .deleted, !file.isBinary,
            loadingFullFiles.insert(path).inserted
        else { return }
        let id = pullRequestID
        let loader = loader
        defer { loadingFullFiles.remove(path) }
        // Loaded and merged off the main actor: large files took noticeable time to build.
        let result = await Task.detached { () -> Result<Hunk?, any Error> in
            do {
                let content = try await loader.loadFileContent(for: id, path: path, ref: headSHA)
                return .success(content.isEmpty ? nil : FullFileBuilder.hunk(newContent: content, diff: file))
            } catch {
                return .failure(error)
            }
        }.value
        // Kept even if the reviewer moved on meanwhile (valid for this head), dropped for another pull request.
        guard self.pullRequestID == id, self.headSHA == headSHA else { return }
        switch result {
        case .success(let hunk?): fullFileHunks[path] = hunk
        case .failure(let error) where !(error is CancellationError):
            lastError = String(localized: "Couldn't load \(file.fileName): \(error.localizedDescription)")
        default: break
        }
    }
}
