import Foundation
import SylvraCore
import Testing

@testable import FeatureInbox

struct InboxTodoListTests {
    private func pr(_ number: Int, title: String = "t") -> PullRequestSummary {
        PullRequestSummary(
            id: PullRequestID(owner: "o", repository: "r", number: number), title: title,
            author: UserRef(login: "a"), createdAt: .distantPast, updatedAt: .distantPast, additions: 1,
            deletions: 0, headRefName: "h\(number)", baseRefName: "main")
    }

    private func numbers(_ list: InboxTodoList) -> [Int] { list.ids.map(\.number) }

    @Test func addsOnceAtTheEndAndRemoves() {
        var list = InboxTodoList()
        list.add(pr(1))
        list.add(pr(2))
        list.add(pr(1))
        #expect(numbers(list) == [1, 2])
        list.remove(pr(1).id)
        #expect(numbers(list) == [2])
    }

    @Test func reordersByDragAndByStep() {
        var list = InboxTodoList([pr(1), pr(2), pr(3)])
        list.move(fromOffsets: [2], toOffset: 0)
        #expect(numbers(list) == [3, 1, 2])
        list.move(pr(3).id, by: 1)
        #expect(numbers(list) == [1, 3, 2])
        list.move(pr(2).id, by: -Int.max / 2)
        #expect(numbers(list) == [2, 1, 3])
        list.move(pr(3).id, by: 5)
        #expect(numbers(list) == [2, 1, 3])
    }

    @Test func keepsTheLatestSummaries() {
        var list = InboxTodoList([pr(1, title: "old"), pr(2, title: "gone")])
        let changed = list.update { $0.number == 1 ? pr(1, title: "new") : nil }
        #expect(changed)
        #expect(list.entries.map(\.title) == ["new", "gone"])
        #expect(!list.update { $0.number == 1 ? pr(1, title: "new") : nil })
    }
}

@MainActor
struct InboxTodoModelTests {
    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "InboxTodoTests-\(UUID().uuidString)"))
    }

    @Test func todosLeaveTheirSectionAndComeBackWhenDone() async throws {
        let model = InboxScreenModel(loader: DemoInboxLoader())
        await model.refresh()
        let first = try #require(model.snapshot.pullRequests(in: .requestedFromMe).first)
        model.addTodo(first)
        #expect(model.isTodo(first.id))
        #expect(model.visibleTodos.map(\.id) == [first.id])
        #expect(!model.visibleSections.flatMap(\.pullRequests).contains { $0.id == first.id })

        model.removeTodo(first.id)
        #expect(model.visibleTodos.isEmpty)
        #expect(model.visibleSections.first { $0.section == .requestedFromMe }?.pullRequests.contains(first) == true)
    }

    @Test func persistsTheOrder() async throws {
        let defaults = try defaults()
        let model = InboxScreenModel(loader: DemoInboxLoader(), defaults: defaults)
        await model.refresh()
        let pullRequests = Array(model.snapshot.pullRequests(in: .myTeams).prefix(3))
        pullRequests.forEach(model.addTodo)
        model.moveTodos(fromOffsets: [2], toOffset: 0)

        let restored = InboxScreenModel(loader: DemoInboxLoader(), defaults: defaults)
        let expected = [pullRequests[2], pullRequests[0], pullRequests[1]].map(\.id)
        #expect(restored.todos.ids == expected)
        // Listed and selectable before the inbox has loaded.
        #expect(restored.visibleTodos.map(\.id) == expected)
        #expect(restored.summary(for: pullRequests[2].id) != nil)
    }

    @Test func searchFiltersButFiltersDont() async throws {
        let model = InboxScreenModel(loader: DemoInboxLoader())
        await model.refresh()
        let pullRequest = try #require(model.snapshot.pullRequests(in: .myTeams).first)
        model.addTodo(pullRequest)
        model.updatePreferences { $0.hideAuthor(pullRequest.author.login) }
        #expect(model.visibleTodos.map(\.id) == [pullRequest.id])
        model.searchText = "zzz-no-match"
        #expect(model.visibleTodos.isEmpty)
    }

    @Test func marksClosedTodos() async throws {
        let model = InboxScreenModel(loader: DemoInboxLoader())
        await model.refresh()
        let closed = try #require(model.snapshot.pullRequests(in: .recentlyClosed).first)
        let open = try #require(model.snapshot.pullRequests(in: .myTeams).first)
        #expect(model.isClosed(closed.id))
        #expect(!model.isClosed(open.id))
    }
}
