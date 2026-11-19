import Foundation
import SylvraCore

/// The worktrees Sylvra created, as JSON next to them. Every change is a read-modify-write under one lock, so
/// several `CheckoutService` values (IDE, terminal, AI) can record concurrently.
public struct WorktreeRegistry: Sendable {
    let file: URL

    public init(storageRoot: URL) {
        file = storageRoot.appending(path: "worktrees.json")
    }

    public func records() async -> [WorktreeRecord] {
        (try? await RepositoryLocks.shared.withLock(lockKey) { load() }) ?? []
    }

    /// Notes that `path` was (re)used for `pullRequest`.
    func recordUse(
        path: URL, purpose: CheckoutService.Purpose, pullRequest: PullRequestID?, clone: URL, now: Date = .now
    ) async {
        await update { records in
            if let index = records.firstIndex(where: { $0.path == path.path }) {
                records[index].pullRequest = pullRequest
                records[index].clonePath = clone.path
                records[index].lastUsedAt = now
            } else {
                records.append(
                    WorktreeRecord(
                        path: path.path, purpose: purpose, pullRequest: pullRequest, clonePath: clone.path,
                        createdAt: now, lastUsedAt: now))
            }
        }
    }

    func update(_ change: @escaping @Sendable (inout [WorktreeRecord]) -> Void) async {
        _ = try? await RepositoryLocks.shared.withLock(lockKey) {
            var records = load()
            change(&records)
            save(records)
        }
    }

    private var lockKey: String { "registry:" + file.path }

    private func load() -> [WorktreeRecord] {
        guard let data = try? Data(contentsOf: file) else { return [] }
        return (try? JSONDecoder.registry.decode([WorktreeRecord].self, from: data)) ?? []
    }

    private func save(_ records: [WorktreeRecord]) {
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? JSONEncoder.registry.encode(records).write(to: file, options: .atomic)
    }
}

extension JSONDecoder {
    fileprivate static var registry: JSONDecoder {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return decoder
    }
}

extension JSONEncoder {
    fileprivate static var registry: JSONEncoder {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        encoder.outputFormatting = [.prettyPrinted, .sortedKeys]
        return encoder
    }
}
