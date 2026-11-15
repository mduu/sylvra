import Foundation

/// Collects the repository's AI setup as review context (see specs/architecture.md §8.3):
/// `AGENTS.md`, `CLAUDE.md` (with `@file` imports), `README.md` and files in folders they reference
/// (typically `specs/`, `docs/`, `ai/`).
public struct RepoContextDiscovery: Sendable {
    public var maxTotalBytes = 80_000
    public var maxFileBytes = 20_000

    public init() {}

    public func documents(in root: URL) -> [ContextDocument] {
        var result: [ContextDocument] = []
        var seen = Set<String>()
        var budget = maxTotalBytes

        func add(_ relativePath: String) {
            let normalized = (relativePath as NSString).standardizingPath
            guard !normalized.hasPrefix(".."), !seen.contains(normalized), budget > 0 else { return }
            let url = root.appending(path: normalized).resolvingSymlinksInPath()
            // Never follow links out of the checkout (a PR could point docs/x.md at ~/.ssh/config).
            let rootPath = root.resolvingSymlinksInPath().path + "/"
            guard url.path.hasPrefix(rootPath), let data = try? Data(contentsOf: url),
                let text = String(data: data, encoding: .utf8)
            else { return }
            seen.insert(normalized)
            let content = String(text.prefix(min(maxFileBytes, budget)))
            budget -= content.utf8.count
            result.append(ContextDocument(path: normalized, content: content))
            for reference in references(in: text) { add(reference) }
        }

        for name in ["AGENTS.md", "CLAUDE.md", ".github/copilot-instructions.md", "README.md"] { add(name) }
        for folder in referencedFolders(in: result) {
            for file in markdownFiles(in: root.appending(path: folder)) { add("\(folder)/\(file)") }
        }
        return result
    }

    /// `@path` imports and relative Markdown links to `.md` files.
    func references(in text: String) -> [String] {
        var paths: [String] = []
        for line in text.split(separator: "\n") {
            let trimmed = line.trimmingCharacters(in: .whitespaces)
            if trimmed.hasPrefix("@"), !trimmed.contains(" ") { paths.append(String(trimmed.dropFirst())) }
        }
        let pattern = /\]\((?!https?:)([^)\s#]+\.md)\)/
        for match in text.matches(of: pattern) { paths.append(String(match.1)) }
        return paths
    }

    /// Well-known context folders mentioned in the collected documents.
    func referencedFolders(in documents: [ContextDocument]) -> [String] {
        let all = documents.map(\.content).joined(separator: "\n")
        return ["specs", "docs", "ai", "doc", "adr", "docs/adr"].filter { all.contains("\($0)/") }
    }

    private func markdownFiles(in folder: URL) -> [String] {
        ((try? FileManager.default.contentsOfDirectory(atPath: folder.path)) ?? [])
            .filter { $0.hasSuffix(".md") }
            .sorted()
    }
}
