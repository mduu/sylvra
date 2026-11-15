import Foundation
import Platform

/// Finds the user's local clone of a GitHub repository by scanning well-known folders.
public struct RepositoryLocator: Sendable {
    private let git: GitRunner
    private let roots: [URL]
    private let maxDepth: Int

    public static var defaultRoots: [URL] {
        let home = FileManager.default.homeDirectoryForCurrentUser
        return ["Dev", "Developer", "Projects", "Code", "src", "Source", "Repos", "GitHub", "Documents/GitHub"]
            .map { home.appending(path: $0) }
    }

    public init(git: GitRunner = GitRunner(), roots: [URL] = RepositoryLocator.defaultRoots, maxDepth: Int = 3) {
        self.git = git
        self.roots = roots
        self.maxDepth = maxDepth
    }

    /// The first git repository whose `origin` points to `owner/name`, or `nil`.
    public func localClone(owner: String, name: String) async -> URL? {
        for candidate in candidates(named: name) {
            guard let remote = try? await git.run(["config", "--get", "remote.origin.url"], in: candidate),
                let parsed = GitHubRemote.ownerAndName(from: remote),
                parsed.owner.caseInsensitiveCompare(owner) == .orderedSame,
                parsed.name.caseInsensitiveCompare(name) == .orderedSame
            else { continue }
            return candidate
        }
        return nil
    }

    /// Directories containing a `.git` folder; folders named like the repository first.
    func candidates(named name: String) -> [URL] {
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
        return found.sorted { lhs, _ in lhs.lastPathComponent.caseInsensitiveCompare(name) == .orderedSame }
    }
}
