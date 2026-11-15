import SylvraCore
import Testing

@testable import FeatureDiff

struct FullFileBuilderTests {
    @Test func mergesDiffIntoFullContent() throws {
        let file = try #require(UnifiedDiffParser.parse(DemoDiffLoader.diff).first)
        let hunk = FullFileBuilder.hunk(newContent: DemoDiffLoader.invoiceServiceHead, diff: file)
        #expect(hunk.lines.first?.text == "import Foundation")
        #expect(hunk.lines.count { $0.kind == .added } == file.additions)
        #expect(hunk.lines.count { $0.kind == .removed } == file.deletions)
        // Old line numbers continue correctly after the changes.
        let last = try #require(hunk.lines.last)
        #expect(last.kind == .context && last.newNumber == 19 && last.oldNumber == 14)
    }
}

@MainActor
struct DiffScreenModelTests {
    private let id = PullRequestID(owner: "acme", repository: "billing", number: 1234)

    @Test func collapsesViewedAndNoiseFiles() async throws {
        let model = DiffScreenModel(loader: DemoDiffLoader())
        await model.load(id, headSHA: "head")
        let lockfile = try #require(model.files.first { $0.path == "Package.resolved" })
        let viewed = try #require(model.files.first { $0.path == "Sources/Billing/Invoice.swift" })
        #expect(model.isCollapsed(lockfile))
        #expect(model.isCollapsed(viewed))
        #expect(model.orderedFiles.last?.path == "Package.resolved")
        model.toggleExpanded(viewed.path)
        #expect(!model.isCollapsed(viewed))
    }

    @Test func togglesViewedState() async {
        let model = DiffScreenModel(loader: DemoDiffLoader())
        await model.load(id, headSHA: "head")
        let path = "Sources/Export/CSVEncoder.swift"
        #expect(!model.isViewed(path))
        await model.toggleViewed(path)
        #expect(model.isViewed(path))
        await model.setViewed(false, folder: "Sources/Export")
        #expect(!model.isViewed(path))
        #expect(model.viewedCount == 2)
    }

    @Test func fullFileScopeUsesFileContent() async throws {
        let model = DiffScreenModel(loader: DemoDiffLoader())
        await model.load(id, headSHA: "head")
        await model.setScope(.fullFile)
        let file = try #require(model.files.first)
        #expect(model.hunks(for: file).count == 1)
        #expect(model.hunks(for: file).first?.lines.first?.text == "import Foundation")
    }
}
