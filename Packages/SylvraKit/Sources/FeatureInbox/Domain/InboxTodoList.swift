import Foundation
import SylvraCore

/// The reviewer's own to-do list of pull requests, in the order they chose (persisted). Each entry keeps the last
/// known summary, so a pull request stays listed even when no inbox section finds it any more (added from a
/// repository, merged, closed).
public struct InboxTodoList: Codable, Equatable, Sendable {
    public private(set) var entries: [PullRequestSummary]

    public init(_ entries: [PullRequestSummary] = []) {
        self.entries = entries
    }

    public var isEmpty: Bool { entries.isEmpty }
    public var ids: [PullRequestID] { entries.map(\.id) }

    public func contains(_ id: PullRequestID) -> Bool {
        entries.contains { $0.id == id }
    }

    /// Adds at the end; a pull request already on the list stays where it is.
    public mutating func add(_ pullRequest: PullRequestSummary) {
        guard !contains(pullRequest.id) else { return }
        entries.append(pullRequest)
    }

    public mutating func remove(_ id: PullRequestID) {
        entries.removeAll { $0.id == id }
    }

    public mutating func move(fromOffsets source: IndexSet, toOffset destination: Int) {
        entries.move(fromOffsets: source, toOffset: destination)
    }

    /// Moves a pull request by `offset` places (negative = up), clamped to the list.
    public mutating func move(_ id: PullRequestID, by offset: Int) {
        guard let index = entries.firstIndex(where: { $0.id == id }) else { return }
        let target = min(max(index + offset, 0), entries.count - 1)
        guard target != index else { return }
        entries.insert(entries.remove(at: index), at: target)
    }

    /// Replaces the stored summaries with newer ones (`latest` returns `nil` for pull requests it doesn't know).
    /// Returns whether anything changed.
    @discardableResult
    public mutating func update(with latest: (PullRequestID) -> PullRequestSummary?) -> Bool {
        let updated = entries.map { latest($0.id) ?? $0 }
        guard updated != entries else { return false }
        entries = updated
        return true
    }
}
