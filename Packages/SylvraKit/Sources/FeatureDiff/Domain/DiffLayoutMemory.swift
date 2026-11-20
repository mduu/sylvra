import Foundation
import SylvraCore

/// The diff layout chosen per pull request, kept while the pull request is open and was opened recently.
@MainActor
struct DiffLayoutMemory {
    struct Entry: Codable, Equatable {
        let pullRequest: PullRequestID
        var layout: DiffScreenModel.Layout
        var lastOpened: Date
    }

    static let key = "diff.layoutByPullRequest"
    /// Forgotten when not opened for this long.
    static let timeToLive: TimeInterval = 7 * 24 * 3600

    let defaults: UserDefaults

    var entries: [Entry] {
        get { defaults.data(forKey: Self.key).flatMap { try? JSONDecoder().decode([Entry].self, from: $0) } ?? [] }
        nonmutating set { defaults.set(try? JSONEncoder().encode(newValue), forKey: Self.key) }
    }

    /// The layout last used for the pull request (and notes that it was opened now).
    func layout(for id: PullRequestID, now: Date = .now) -> DiffScreenModel.Layout? {
        var all = entries
        guard let index = all.firstIndex(where: { $0.pullRequest == id }) else { return nil }
        all[index].lastOpened = now
        entries = all
        return all[index].layout
    }

    func remember(_ layout: DiffScreenModel.Layout, for id: PullRequestID, now: Date = .now) {
        entries = entries.filter { $0.pullRequest != id } + [Entry(pullRequest: id, layout: layout, lastOpened: now)]
    }

    /// Forgets pull requests not opened within `timeToLive` and those no longer open (merged or closed);
    /// `isOpen` returning `nil` (unknown, e.g. offline) keeps the entry.
    func prune(now: Date = .now, isOpen: @Sendable (PullRequestID) async -> Bool?) async {
        var forgotten: Set<PullRequestID> = []
        for entry in entries {
            if now.timeIntervalSince(entry.lastOpened) >= Self.timeToLive {
                forgotten.insert(entry.pullRequest)
            } else if await isOpen(entry.pullRequest) == false {
                forgotten.insert(entry.pullRequest)
            }
        }
        // Read again: layouts chosen while GitHub was asked stay.
        entries = entries.filter { !forgotten.contains($0.pullRequest) }
    }
}
