import Foundation
import Testing

@testable import FeatureDiff

@MainActor
@Suite struct DiffLayoutMemoryTests {
    @Test func keepsTheChosenLayoutAcrossLaunches() throws {
        let defaults = try #require(UserDefaults(suiteName: "DiffLayoutMemoryTests-\(UUID().uuidString)"))
        let first = DiffScreenModel(loader: DemoDiffLoader(), defaults: defaults)
        #expect(first.layout == .sideBySide)
        first.layout = .inline
        #expect(DiffScreenModel(loader: DemoDiffLoader(), defaults: defaults).layout == .inline)
    }

    @Test func demoLaunchesDontRemember() {
        let model = DiffScreenModel(loader: DemoDiffLoader())
        model.layout = .inline
        #expect(DiffScreenModel(loader: DemoDiffLoader()).layout == .sideBySide)
    }
}
