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

struct ChangeMapTooltipTests {
    @Test func tooltipNamesTheFullFolderAndLines() {
        let tile = ChangeMapView.Tile(folder: "Sources/Billing/Pricing", additions: 9, deletions: 3)
        #expect(ChangeMapView.tooltip(for: tile) == "Sources/Billing/Pricing · +9 −3")
        #expect(ChangeMapView.name(of: tile) == "Pricing")
        #expect(ChangeMapView.name(of: .init(folder: "", additions: 1, deletions: 0)) == "/")
    }
}

@MainActor
struct RevealTests {
    @Test func revealsCollapsedFilesAndLeavesCommitsWithoutThem() async {
        let id = PullRequestID(owner: "acme", repository: "billing", number: 1234)
        let model = DiffScreenModel(loader: DemoDiffLoader())
        await model.load(id, headSHA: "e08b5a1")
        let viewed = "Sources/Billing/Invoice.swift"
        #expect(model.files.first { $0.path == viewed }.map(model.isCollapsed) == true)

        await model.reveal(viewed)
        #expect(model.selectedPath == viewed)
        #expect(model.focusedLine?.line == 11)
        #expect(model.files.first { $0.path == viewed }.map(model.isCollapsed) == false)

        model.commits = [
            Commit(sha: "9a1f04c", subject: "CSV", author: UserRef(login: "a"), authoredAt: .now)
        ]
        await model.showCommit(model.commits[0])
        await model.reveal("Sources/Billing/InvoiceService.swift")
        #expect(model.selectedCommit == nil)
        #expect(model.selectedPath == "Sources/Billing/InvoiceService.swift")
    }
}

@MainActor
struct RevealLineTests {
    @Test func revealsARequestedLine() async {
        let model = DiffScreenModel(loader: DemoDiffLoader())
        await model.load(PullRequestID(owner: "acme", repository: "billing", number: 1234), headSHA: "e08b5a1")
        await model.reveal("Sources/Billing/InvoiceService.swift", line: 13)
        #expect(model.focusedLine?.line == 13)
        #expect(model.selectedPath == "Sources/Billing/InvoiceService.swift")
    }
}
