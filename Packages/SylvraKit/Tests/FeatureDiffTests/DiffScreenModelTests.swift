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

    @Test func fullFileScopeShowsOnlyTheSelectedFileInFull() async throws {
        let model = DiffScreenModel(loader: DemoDiffLoader())
        await model.load(id, headSHA: "head")
        let selected = "Sources/Billing/InvoiceService.swift"
        model.selectedPath = selected
        await model.setScope(.fullFile)
        #expect(model.shownFiles.map(\.path) == [selected])
        let file = try #require(model.shownFiles.first)
        #expect(model.hunks(for: file).count == 1)
        #expect(model.hunks(for: file).first?.lines.first?.text == "import Foundation")
        // Only the shown file was loaded.
        #expect(Array(model.fullFileHunks.keys) == [selected])

        let other = try #require(model.orderedFiles.first { $0.path != selected && !$0.isBinary })
        model.selectedPath = other.path
        #expect(model.shownFiles.map(\.path) == [other.path])

        await model.setScope(.focused)
        #expect(model.shownFiles.count == model.orderedFiles.count)
    }

    @Test func fullFileScopeLoadsOnlyTheShownFile() async {
        let loader = RecordingContentLoader()
        let model = DiffScreenModel(loader: loader)
        await model.load(id, headSHA: "head")
        await model.setScope(.fullFile)
        #expect(await loader.requested == [model.fullFilePath].compactMap { $0 })
        await model.loadFullFile()
        #expect(await loader.requested.count == 1)
    }

    /// Regression: the head SHA arriving with the PR details restarted the diff load (fetched twice).
    @Test func learningTheHeadDoesNotLoadTheDiffAgain() async {
        let loader = RecordingContentLoader()
        let model = DiffScreenModel(loader: loader)
        await model.load(id, headSHA: nil)
        await model.headChanged(to: "head", for: id)
        #expect(await loader.diffLoads == 1)
        // A push moves the head: that loads the diff again.
        await model.headChanged(to: "pushed", for: id)
        #expect(await loader.diffLoads == 2)
        // Another pull request's head is ignored (its own load follows the selection).
        await model.headChanged(to: "other", for: PullRequestID(owner: "o", repository: "r", number: 1))
        #expect(await loader.diffLoads == 2)
    }

    @Test func fullFileScopeWithoutSelectionShowsTheFirstFile() async {
        let model = DiffScreenModel(loader: DemoDiffLoader())
        await model.load(id, headSHA: "head")
        await model.setScope(.fullFile)
        #expect(model.shownFiles.map(\.path) == [model.orderedFiles.first?.path].compactMap { $0 })
        #expect(!model.isLoadingScope)
    }

    @Test func returnsTextOfLinesOnEachSide() async {
        let model = DiffScreenModel(loader: DemoDiffLoader())
        await model.load(id, headSHA: nil)
        let path = "Sources/Billing/InvoiceService.swift"
        #expect(
            model.text(at: CodeLocation(path: path, line: 8, side: .left))
                == "        invoice.items.reduce(0) { $0 + $1.price }")
        #expect(
            model.text(at: CodeLocation(path: path, line: 10, side: .right, startLine: 9))
                == "            sum + (item.price * item.quantity).rounded(2)\n        }")
        #expect(model.text(at: CodeLocation(path: "missing", line: 1, side: .right)).isEmpty)
    }
}

@MainActor
struct SinceLastReviewTests {
    private let id = PullRequestID(owner: "acme", repository: "billing", number: 1234)

    @Test func showsOnlyChangesSinceLastReview() async {
        let model = DiffScreenModel(loader: DemoDiffLoader())
        await model.load(id, headSHA: "e08b5a1")
        #expect(model.progress?.hasChangesSinceReview == true)
        #expect(model.files.count == 6)
        await model.setScope(.sinceLastReview)
        #expect(model.files.map(\.path) == ["Sources/Billing/Invoice.swift", "Sources/Export/CSVEncoder.swift"])
        await model.setScope(.focused)
        #expect(model.files.count == 6)
    }

    @Test func detectsNewPushes() async throws {
        let model = DiffScreenModel(loader: DemoDiffLoader(simulatesPush: true))
        await model.load(id, headSHA: "e08b5a1")
        await model.checkForNewCommits()
        #expect(!model.hasNewCommits)
        try await Task.sleep(for: .seconds(3.2))
        await model.checkForNewCommits()
        #expect(model.hasNewCommits)
    }

    @Test func progressWithoutPreviousReviewHasNoChangesSinceReview() {
        #expect(!ReviewProgress(headSHA: "a").hasChangesSinceReview)
        #expect(!ReviewProgress(headSHA: "a", lastReviewedSHA: "a").hasChangesSinceReview)
    }
}

@MainActor
struct ReadingOrderTests {
    @Test func sortsFilesByReadingOrderAndKeepsNoiseLast() async {
        let model = DiffScreenModel(loader: DemoDiffLoader())
        await model.load(PullRequestID(owner: "acme", repository: "billing", number: 1234), headSHA: "h")
        model.readingOrder = [
            ReadingStep(path: "Sources/Export/CSVEncoder.swift", reason: "risky", isRisky: true),
            ReadingStep(path: "Sources/Billing/Invoice.swift", reason: "model"),
        ]
        let paths = model.orderedFiles.map(\.path)
        #expect(paths.prefix(2) == ["Sources/Export/CSVEncoder.swift", "Sources/Billing/Invoice.swift"])
        #expect(paths.last == "Package.resolved")
        #expect(model.readingStep(for: "Sources/Billing/Invoice.swift")?.number == 2)
        model.usesReadingOrder = false
        #expect(model.orderedFiles.first?.path == "Sources/Billing/InvoiceService.swift")
    }
}

@MainActor
struct DiffNavigationTests {
    private let id = PullRequestID(owner: "acme", repository: "billing", number: 1234)

    @Test func changeLinesAnchorRemovalsAtTheNextNewLine() throws {
        let file = try #require(UnifiedDiffParser.parse(DemoDiffLoader.diff).first)
        // Hunk 1: line 8 (removal + additions start), line 13 (export signature).
        #expect(DiffScreenModel.changeLines(in: file.hunks) == [8, 13])
    }

    @Test func jumpsThroughChangesInReviewOrder() async {
        let model = DiffScreenModel(loader: DemoDiffLoader())
        await model.load(id, headSHA: "h")
        model.selectChange(offset: 1)
        #expect(model.focusedLine?.path == "Sources/Billing/InvoiceService.swift")
        #expect(model.focusedLine?.line == 8)
        model.selectChange(offset: 1)
        #expect(model.focusedLine?.line == 13)
        model.selectChange(offset: 1)
        #expect(model.focusedLine?.path == "Sources/Export/CSVEncoder.swift")
        model.selectChange(offset: -1)
        #expect(model.focusedLine?.line == 13)
    }

    @Test func findsMatchesAcrossFilesAndWraps() async {
        let model = DiffScreenModel(loader: DemoDiffLoader())
        await model.load(id, headSHA: "h")
        model.searchQuery = "quantity"
        let matches = model.searchMatches
        #expect(matches.count >= 3)
        #expect(Set(matches.map(\.path)).contains("Sources/Billing/Invoice.swift"))
        model.selectSearchMatch(offset: -1)
        #expect(model.currentSearchMatch == matches.last)
        model.selectSearchMatch(offset: 1)
        #expect(model.currentSearchMatch == matches.first)
        // The viewed (collapsed) file expands when its match is shown.
        model.searchQuery = "let quantity"
        model.selectSearchMatch(offset: 1)
        #expect(model.focusedLine?.path == "Sources/Billing/Invoice.swift")
        #expect(model.expandedPaths.contains("Sources/Billing/Invoice.swift"))
        model.searchQuery = "q"
        #expect(model.searchMatches.isEmpty)
    }
}

struct ContextExpanderTests {
    private let head = (1...40).map { "line \($0)" }

    private var hunks: [Hunk] {
        [
            Hunk(
                oldStart: 10, oldCount: 2, newStart: 12, newCount: 2,
                lines: [
                    DiffLine(kind: .context, oldNumber: 10, newNumber: 12, text: "line 12"),
                    DiffLine(kind: .added, oldNumber: nil, newNumber: 13, text: "line 13"),
                ]),
            Hunk(
                oldStart: 30, oldCount: 1, newStart: 33, newCount: 1,
                lines: [
                    DiffLine(kind: .context, oldNumber: 30, newNumber: 33, text: "line 33")
                ]),
        ]
    }

    @Test func countsHiddenLinesAboveEachHunk() {
        #expect(ContextExpander.hiddenAbove(hunks) == [11, 19])
    }

    @Test func revealsLinesAboveWithMatchingOldNumbers() {
        let expanded = ContextExpander.expand(hunks, revealed: [0: 3, 1: 50], headLines: head)
        #expect(expanded[0].lines.prefix(3).map(\.newNumber) == [9, 10, 11])
        #expect(expanded[0].lines.first?.oldNumber == 7)
        #expect(expanded[0].lines.first?.text == "line 9")
        #expect(expanded[0].newStart == 9)
        #expect(expanded[1].lines.count == 20)  // clamped to the 19-line gap
        #expect(ContextExpander.hiddenAbove(expanded) == [8, 0])
    }
}

@MainActor
struct ContextExpansionModelTests {
    @Test func expandsStepByStepUsingTheHeadFile() async throws {
        let model = DiffScreenModel(loader: DemoDiffLoader())
        await model.load(PullRequestID(owner: "acme", repository: "billing", number: 1234), headSHA: "h")
        let file = try #require(model.files.first { $0.path == "Sources/Billing/InvoiceService.swift" })
        #expect(model.hiddenAbove(file) == [3])
        await model.expandContext(file, hunk: 0, by: 2)
        #expect(model.hiddenAbove(file) == [1])
        #expect(model.hunks(for: file).first?.lines.first?.text == "")
        await model.expandContext(file, hunk: 0, by: nil)
        #expect(model.hiddenAbove(file) == [0])
        #expect(model.hunks(for: file).first?.lines.first?.text == "import Foundation")
    }
}

/// The demo diff, recording which files' contents were asked for.
private actor RecordingContentLoader: DiffLoading {
    private let demo = DemoDiffLoader()
    private(set) var requested: [String] = []
    private(set) var diffLoads = 0

    func loadDiff(for id: PullRequestID) async throws -> PullRequestDiff {
        diffLoads += 1
        return try await demo.loadDiff(for: id)
    }
    func loadFileContent(for id: PullRequestID, path: String, ref: String) async throws -> String {
        requested.append(path)
        return "line"
    }
    func setViewed(_ viewed: Bool, path: String, pullRequestNodeID: String) async throws {}
    func loadReviewProgress(for id: PullRequestID) async throws -> ReviewProgress {
        try await demo.loadReviewProgress(for: id)
    }
    func loadDiff(for id: PullRequestID, from base: String, to head: String) async throws -> [FileDiff] {
        try await demo.loadDiff(for: id, from: base, to: head)
    }
}
