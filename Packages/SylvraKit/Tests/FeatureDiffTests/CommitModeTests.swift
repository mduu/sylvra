import Foundation
import SylvraCore
import Testing

@testable import FeatureDiff

@MainActor
struct CommitModeTests {
    private let id = PullRequestID(owner: "acme", repository: "billing", number: 1234)
    private let commits = [
        "9a1f04c3b2e1d0a9f8e7d6c5b4a39281706f5e4d", "3be7d12f0e9d8c7b6a5f4e3d2c1b0a9f8e7d6c5b",
        "c40e9a8d7c6b5a4f3e2d1c0b9a8f7e6d5c4b3a29", "e08b5a1c2d3e4f5a6b7c8d9e0f1a2b3c4d5e6f7a",
    ].enumerated().map { index, sha in
        Commit(sha: sha, subject: "Commit \(index + 1)", author: UserRef(login: "lkeller"), authoredAt: .now)
    }

    private func model() async -> DiffScreenModel {
        let model = DiffScreenModel(loader: DemoDiffLoader())
        await model.load(id, headSHA: "e08b5a1")
        model.commits = commits
        return model
    }

    @Test func showsOneCommitAndGoesBack() async {
        let model = await model()
        let allFiles = model.files.count
        await model.showCommit(commits[1])
        #expect(
            model.files.map(\.path).sorted() == [
                "Sources/Billing/InvoiceService.swift", "Sources/Export/ExportFormat.swift",
            ])
        #expect(model.commitPosition?.number == 2)
        #expect(model.commitPosition?.count == 4)
        await model.showCommit(nil)
        #expect(model.files.count == allFiles)
        #expect(model.commitPosition == nil)
    }

    @Test func stepsThroughCommitsAndStopsAtTheEnds() async {
        let model = await model()
        await model.selectCommit(offset: 1)
        #expect(model.selectedCommit == commits[0])
        await model.selectCommit(offset: -1)
        #expect(model.selectedCommit == commits[0])
        for _ in 0..<5 { await model.selectCommit(offset: 1) }
        #expect(model.selectedCommit == commits[3])
        await model.showCommit(nil)
        await model.selectCommit(offset: -1)
        #expect(model.selectedCommit == commits[3])
    }

    @Test func leavesCommitModeWhenThePullRequestChanges() async {
        let model = await model()
        await model.showCommit(commits[0])
        await model.load(PullRequestID(owner: "acme", repository: "billing", number: 1), headSHA: "x")
        #expect(model.selectedCommit == nil)
    }

    @Test func changeMapGroupsFoldersWithoutNoise() async {
        let model = await model()
        let tiles = ChangeMapView.tiles(for: model.orderedFiles)
        #expect(!tiles.contains { $0.folder.isEmpty && $0.additions == 1 })  // Package.resolved is noise
        #expect(tiles.first?.folder == "Sources/Export")
        #expect(tiles.map(\.weight) == tiles.map(\.weight).sorted(by: >))
    }
}
