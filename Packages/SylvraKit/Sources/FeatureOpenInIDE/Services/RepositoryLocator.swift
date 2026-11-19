import Foundation
import Platform

/// Finds the user's local clone of a GitHub repository: the configured folders first, then Spotlight (anywhere in
/// the home folder), so Sylvra never clones a repository the user already has (`RepositorySearchSettings`).
public struct RepositoryLocator: Sendable {
    /// Folders named like a repository, anywhere on disk (`nil`: no Spotlight search, e.g. in tests).
    public typealias FolderSearch = @Sendable (_ name: String) async -> [URL]

    private let git: GitRunner
    /// `nil`: the folders from `RepositorySearchSettings` at the time of the search.
    private let roots: [URL]?
    private let maxDepth: Int
    private let search: FolderSearch?

    public init(
        git: GitRunner = GitRunner(), roots: [URL]? = nil, maxDepth: Int = 3,
        search: FolderSearch? = RepositoryLocator.spotlight
    ) {
        self.git = git
        self.roots = roots
        self.maxDepth = maxDepth
        self.search = search
    }

    /// The first git repository whose `origin` points to `owner/name`, or `nil`.
    public func localClone(owner: String, name: String) async -> URL? {
        let settings = roots == nil ? RepositorySearchSettings.load() : nil
        let folders = roots ?? settings?.folderURLs ?? []
        if let found = await firstClone(in: candidates(named: name, in: folders), owner: owner, name: name) {
            return found
        }
        guard let search, settings?.usesSpotlight ?? true else { return nil }
        let found = await search(name).filter(Self.isUserClone)
        return await firstClone(in: found, owner: owner, name: name)
    }

    private func firstClone(in candidates: [URL], owner: String, name: String) async -> URL? {
        for candidate in candidates {
            guard let remote = try? await git.run(["config", "--get", "remote.origin.url"], in: candidate),
                let parsed = GitHubRemote.ownerAndName(from: remote),
                parsed.owner.caseInsensitiveCompare(owner) == .orderedSame,
                parsed.name.caseInsensitiveCompare(name) == .orderedSame
            else { continue }
            return candidate
        }
        return nil
    }

    /// A real clone (`.git` is a folder, not a worktree's `.git` file) outside `~/Library` (Sylvra's own
    /// worktrees and clones, app caches).
    nonisolated static func isUserClone(_ url: URL) -> Bool {
        var isDirectory: ObjCBool = false
        let library = FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library").path + "/"
        return !url.path.hasPrefix(library)
            && FileManager.default.fileExists(atPath: url.appending(path: ".git").path, isDirectory: &isDirectory)
            && isDirectory.boolValue
    }

    /// Spotlight: folders in the home folder named `name` (case-insensitive).
    public static let spotlight: FolderSearch = { name in
        // GitHub repository names only contain letters, digits, `.`, `-` and `_`; anything else is not searched.
        guard !name.isEmpty, name.allSatisfy({ $0.isLetter || $0.isNumber || ".-_".contains($0) }),
            let result = try? await SystemProcessRunner().run(
                URL(fileURLWithPath: "/usr/bin/mdfind"),
                arguments: [
                    "-onlyin", FileManager.default.homeDirectoryForCurrentUser.path,
                    "kMDItemFSName == '\(name)'c && kMDItemContentType == 'public.folder'",
                ], workingDirectory: nil),
            result.exitCode == 0
        else { return [] }
        return result.standardOutput.split(separator: "\n").map { URL(fileURLWithPath: String($0)) }
    }

    /// Directories containing a `.git` folder; folders named like the repository first.
    func candidates(named name: String, in roots: [URL]) -> [URL] {
        var found: [URL] = []
        let fileManager = FileManager.default
        func visit(_ directory: URL, depth: Int) {
            if fileManager.fileExists(atPath: directory.appending(path: ".git").path) {
                found.append(directory)
                return
            }
            guard depth < maxDepth,
                let children = try? fileManager.contentsOfDirectory(
                    at: directory, includingPropertiesForKeys: [.isDirectoryKey], options: [.skipsHiddenFiles])
            else { return }
            for child in children where (try? child.resourceValues(forKeys: [.isDirectoryKey]).isDirectory) == true {
                visit(child, depth: depth + 1)
            }
        }
        for root in roots where fileManager.fileExists(atPath: root.path) {
            visit(root, depth: 0)
        }
        let named = found.filter { $0.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame }
        return named + found.filter { $0.lastPathComponent.caseInsensitiveCompare(name) != .orderedSame }
    }
}
