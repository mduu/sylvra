import Foundation
import Platform
import SylvraCore
import Testing

@testable import FeatureDelivery

/// Answers with the demo delivery and records which logs were loaded.
private final class DemoWithLogs: DeliveryLoading, @unchecked Sendable {
    var loadedLogs: [Int] = []
    var deliveryLoads = 0
    func loadDelivery(for id: PullRequestID) async throws -> Delivery? {
        deliveryLoads += 1
        return DemoDeliveryLoader.delivery(for: id)
    }
    func approve(_ approval: DeliveryStage.Approval) async throws {}
    func loadLog(jobID: Int, in id: PullRequestID) async throws -> String {
        loadedLogs.append(jobID)
        return "2026-11-26T14:30:43.4Z ##[error]boom"
    }
}

@MainActor
struct DeliveryViewModelTests {
    private let id = PullRequestID(owner: "acme", repository: "billing", number: 812)

    @Test func mergedPullRequestsShowTheirDeliveryUntilSwitchedToTheDiff() {
        let model = DeliveryModel(loader: DemoWithLogs())
        #expect(model.showsDelivery(id, isMerged: true))
        #expect(!model.showsDelivery(id, isMerged: false))
        model.setShowsDelivery(false, for: id)
        #expect(!model.showsDelivery(id, isMerged: true))
        model.setShowsDelivery(true, for: id)
        #expect(model.showsDelivery(id, isMerged: true))
    }

    @Test func detailsStartWithWhatMattersAndAJobClickShowsItsLog() async throws {
        let loader = DemoWithLogs()
        let model = DeliveryModel(loader: loader)
        await model.load(id)
        // The current stage (test) runs: its running job first.
        #expect(model.shownStage(for: id)?.name == "test")
        #expect(model.shownItem(for: id) == .job("Deploy test"))

        // A click on a box in another stage selects that stage and the job, and loads its log.
        model.selectJob("Deploy dev", of: id)
        #expect(model.shownStage(for: id)?.name == "dev" && model.shownItem(for: id) == .job("Deploy dev"))
        let number = try #require(
            model.delivery(for: id)?.stages.flatMap(\.jobs).first { $0.id == "Deploy dev" }?.jobID)
        await model.loadLog(number, of: id)
        guard case .loaded(let log) = model.logs[number] else {
            Issue.record("log not loaded")
            return
        }
        #expect(log.lines.first?.kind == .error)

        // Selecting the stage again starts with what matters most.
        model.selectStage(model.shownStage(for: id)?.id ?? "", of: id)
        #expect(model.selectedItem[id] == nil)
    }

    @Test func theInboxBadgeComesFromTheDelivery() async {
        let model = DeliveryModel(loader: DemoWithLogs())
        #expect(model.badge(for: id) == nil)
        await model.load(id)
        #expect(model.badge(for: id)?.outcome == .inProgress)
        #expect(model.badge(for: id)?.dots == [.done, .done, .running, .needsApproval])
    }

    /// The inbox shows merged pull requests' deliveries after a restart, and ones still on their way are
    /// brought up to date once.
    @Test func deliveriesSurviveARestart() async throws {
        let directory = FileManager.default.temporaryDirectory.appending(path: "delivery-cache-\(UUID().uuidString)")
        defer { try? FileManager.default.removeItem(at: directory) }
        let cache = JSONCache(directory: directory)
        let loader = DemoWithLogs()
        let first = DeliveryModel(loader: loader, cache: cache)
        await first.load(id)
        let saved = try #require(first.delivery(for: id))
        for _ in 0..<100 where cache.load([Delivery].self, key: DeliveryModel.deliveriesKey) == nil {
            try await Task.sleep(for: .milliseconds(10))
        }

        let restarted = DeliveryModel(loader: loader, cache: cache)
        // Dates come back to the second (the cache stores ISO 8601).
        let restored = try #require(restarted.delivery(for: id))
        #expect(restored.stages.map(\.id) == saved.stages.map(\.id))
        #expect(restored.stages.map(\.state) == saved.stages.map(\.state))
        #expect(restored.stages.flatMap(\.jobs).map(\.needs) == saved.stages.flatMap(\.jobs).map(\.needs))
        #expect(restarted.badge(for: id)?.dots == [.done, .done, .running, .needsApproval])
        // Still on its way: loaded again at launch.
        let loads = loader.deliveryLoads
        await restarted.refreshRestored()
        #expect(loader.deliveryLoads == loads + 1)
    }

    /// Merged pull requests the inbox lists get their delivery without being opened — once per launch.
    @Test func recentlyClosedPullRequestsArePreloadedOnce() async {
        final class Mixed: DeliveryLoading, @unchecked Sendable {
            var loads: [Int] = []
            func loadDelivery(for id: PullRequestID) async throws -> Delivery? {
                loads.append(id.number)
                // #2 was closed without merging; #1 is live.
                guard id.number == 1 else { return nil }
                var delivery = DemoDeliveryLoader.delivery(for: id)
                delivery.stages = delivery.stages.map {
                    DeliveryStage(id: $0.id, name: $0.name, kind: $0.kind, workflow: $0.workflow, state: .succeeded)
                }
                return delivery
            }
            func approve(_ approval: DeliveryStage.Approval) async throws {}
            func loadLog(jobID: Int, in id: PullRequestID) async throws -> String { "" }
        }
        let loader = Mixed()
        let model = DeliveryModel(loader: loader)
        let ids = [1, 2].map { PullRequestID(owner: "acme", repository: "billing", number: $0) }
        await model.preload(ids)
        await model.preload(ids)
        #expect(loader.loads == [1, 2])
        #expect(model.badge(for: ids[0])?.outcome == .healthy && model.badge(for: ids[1]) == nil)
    }
}
