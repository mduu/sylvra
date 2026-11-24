import Foundation
import SylvraCore

/// The reviewer's to-do list on top of the inbox.
extension InboxScreenModel {
    /// The to-do list in the reviewer's order with the latest summaries, matching the search. Filters don't apply:
    /// the reviewer put each one there on purpose.
    public var visibleTodos: [PullRequestSummary] {
        todos.entries.map { latestSummary(for: $0.id) ?? $0 }.filter(matchesSearch)
    }

    public func isTodo(_ id: PullRequestID) -> Bool { todos.contains(id) }

    /// Merged or closed since it was put on the list (only known while *Recently closed* lists it).
    public func isClosed(_ id: PullRequestID) -> Bool {
        let open = InboxSection.allCases.filter { $0 != .recentlyClosed }
        return snapshot.pullRequests(in: .recentlyClosed).contains { $0.id == id }
            && !open.contains { section in snapshot.pullRequests(in: section).contains { $0.id == id } }
    }

    public func addTodo(_ pullRequest: PullRequestSummary) {
        changeTodos { $0.add(pullRequest) }
    }

    /// Done or no longer needed: the pull request goes back to its section (if one still lists it).
    public func removeTodo(_ id: PullRequestID) {
        changeTodos { $0.remove(id) }
    }

    /// Reorders by drag and drop; only while the whole list is shown (no search).
    public func moveTodos(fromOffsets source: IndexSet, toOffset destination: Int) {
        changeTodos { $0.move(fromOffsets: source, toOffset: destination) }
    }

    public func moveTodo(_ id: PullRequestID, by offset: Int) {
        changeTodos { $0.move(id, by: offset) }
    }

    private func changeTodos(_ change: (inout InboxTodoList) -> Void) {
        var changed = todos
        change(&changed)
        guard changed != todos else { return }
        todos = changed
        saveTodos()
    }
}
