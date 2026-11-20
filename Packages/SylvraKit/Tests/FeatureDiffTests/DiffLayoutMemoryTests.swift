import Foundation
import SylvraCore
import Testing

@testable import FeatureDiff

@MainActor
@Suite struct DiffLayoutMemoryTests {
    private let first = PullRequestID(owner: "acme", repository: "billing", number: 1234)
    private let second = PullRequestID(owner: "acme", repository: "billing", number: 881)

    private func defaults() throws -> UserDefaults {
        try #require(UserDefaults(suiteName: "DiffLayoutMemoryTests-\(UUID().uuidString)"))
    }

    @Test func eachPullRequestKeepsItsLayoutAcrossLaunches() async throws {
        let defaults = try defaults()
        let model = DiffScreenModel(loader: DemoDiffLoader(), defaults: defaults)
        await model.load(first, headSHA: nil)
        model.layout = .inline
        await model.load(second, headSHA: nil)
        model.layout = .sideBySide

        let relaunched = DiffScreenModel(loader: DemoDiffLoader(), defaults: defaults)
        await relaunched.load(first, headSHA: nil)
        #expect(relaunched.layout == .inline)
        await relaunched.load(second, headSHA: nil)
        #expect(relaunched.layout == .sideBySide)
    }

    @Test func aNewPullRequestStartsWithTheLastChoice() async throws {
        let defaults = try defaults()
        let model = DiffScreenModel(loader: DemoDiffLoader(), defaults: defaults)
        await model.load(first, headSHA: nil)
        model.layout = .inline
        await model.load(second, headSHA: nil)
        #expect(model.layout == .inline)
    }

    @Test func demoLaunchesDontRemember() async {
        let model = DiffScreenModel(loader: DemoDiffLoader())
        await model.load(first, headSHA: nil)
        model.layout = .inline
        #expect(DiffScreenModel(loader: DemoDiffLoader()).layout == .sideBySide)
    }

    @Test func forgetsClosedAndLongUnopenedPullRequests() async throws {
        let memory = DiffLayoutMemory(defaults: try defaults())
        let now = Date()
        let third = PullRequestID(owner: "acme", repository: "billing", number: 7)
        memory.remember(.inline, for: first, now: now.addingTimeInterval(-8 * 24 * 3600))
        memory.remember(.inline, for: second, now: now)
        memory.remember(.inline, for: third, now: now)
        let closed = second
        await memory.prune(now: now) { $0 == closed ? false : ($0 == third ? nil : true) }
        #expect(memory.entries.map(\.pullRequest) == [third])
    }

    @Test func openingAPullRequestKeepsItsLayoutAlive() throws {
        let memory = DiffLayoutMemory(defaults: try defaults())
        let now = Date()
        memory.remember(.inline, for: first, now: now.addingTimeInterval(-6 * 24 * 3600))
        #expect(memory.layout(for: first, now: now) == .inline)
        #expect(memory.entries.first?.lastOpened == now)
    }
}
