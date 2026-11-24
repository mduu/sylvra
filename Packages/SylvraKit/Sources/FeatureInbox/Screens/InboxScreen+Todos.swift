import DesignSystem
import SwiftUI
import SylvraCore

/// The to-do section of the inbox: check one off when done, drag the rows to reorder.
extension InboxScreen {
    /// The reviewer's to-do list on top, in their order: check one off when done, drag the rows to reorder.
    func todoSection(_ todos: [PullRequestSummary]) -> some View {
        let canReorder = model.searchText.trimmingCharacters(in: .whitespaces).isEmpty
        let move: ((IndexSet, Int) -> Void)? =
            canReorder ? { model.moveTodos(fromOffsets: $0, toOffset: $1) } : nil
        return Section(isExpanded: expansion("todos")) {
            ForEach(todos) { pullRequest in
                todoRow(pullRequest, in: todos, canReorder: canReorder)
            }
            .onMove(perform: move)
        } header: {
            SectionHeading(title: String(localized: "To-Do"), count: todos.count, isProminent: true)
        }
    }

    private func todoRow(_ pullRequest: PullRequestSummary, in todos: [PullRequestSummary], canReorder: Bool)
        -> some View
    {
        InboxTodoRow(
            pullRequest: pullRequest, isDone: completing.contains(pullRequest.id),
            isClosed: model.isClosed(pullRequest.id), canReorder: canReorder,
            markDone: { complete(pullRequest.id) }
        )
        .tag(pullRequest.id)
        .contextMenu {
            todoMenu(
                pullRequest, isFirst: pullRequest.id == todos.first?.id, isLast: pullRequest.id == todos.last?.id,
                canReorder: canReorder)
        }
    }

    @ViewBuilder private func todoMenu(
        _ pullRequest: PullRequestSummary, isFirst: Bool, isLast: Bool, canReorder: Bool
    ) -> some View {
        Button("Mark as Done", systemImage: "checkmark.circle") { complete(pullRequest.id) }
        if canReorder {
            Button("Move Up", systemImage: "arrow.up") { moveTodo(pullRequest.id, by: -1) }
                .disabled(isFirst)
            Button("Move Down", systemImage: "arrow.down") { moveTodo(pullRequest.id, by: 1) }
                .disabled(isLast)
            Button("Move to Top", systemImage: "arrow.up.to.line") { moveTodo(pullRequest.id, by: -Int.max / 2) }
                .disabled(isFirst)
        }
        Divider()
        rowMenu(pullRequest)
    }

    private func moveTodo(_ id: PullRequestID, by offset: Int) {
        withAnimation(.snappy) { model.moveTodo(id, by: offset) }
    }

    func removeTodo(_ id: PullRequestID) {
        withAnimation(.snappy) { model.removeTodo(id) }
    }

    /// Shows the check briefly, then the pull request leaves the list (back to its section, if one lists it).
    private func complete(_ id: PullRequestID) {
        guard completing.insert(id).inserted else { return }
        Task {
            try? await Task.sleep(for: .milliseconds(600))
            removeTodo(id)
            completing.remove(id)
        }
    }
}
