import Foundation
import SylvraCore
import Testing

@testable import FeatureDiff

/// Regression: clicking a finding in the inspector didn't bring its line into view.
@MainActor
struct FocusTests {
    private let id = PullRequestID(owner: "acme", repository: "billing", number: 1234)
    private let path = "Sources/Billing/InvoiceService.swift"

    @Test func keepsAShownLine() async {
        let model = DiffScreenModel(loader: DemoDiffLoader())
        await model.load(id, headSHA: "head")
        model.focus(path: path, line: 10)
        #expect(model.focusedLine?.line == 10)
        #expect(model.selectedPath == path)
    }

    @Test func snapsALineOutsideTheDiffToTheNearestShownLine() async {
        let model = DiffScreenModel(loader: DemoDiffLoader())
        await model.load(id, headSHA: "head")
        model.focus(path: path, line: 60)
        #expect(model.focusedLine?.line == 19)
        model.focus(path: path, line: 1)
        #expect(model.focusedLine?.line == 4)
    }

    @Test func expandsACollapsedFile() async throws {
        let model = DiffScreenModel(loader: DemoDiffLoader())
        await model.load(id, headSHA: "head")
        let viewed = try #require(model.files.first { $0.path == "Sources/Billing/Invoice.swift" })
        #expect(model.isCollapsed(viewed))
        model.focus(path: viewed.path, line: 11)
        #expect(!model.isCollapsed(viewed))
    }

    @Test func revealingAFindingLeavesASingleCommit() async {
        let model = DiffScreenModel(loader: DemoDiffLoader())
        await model.load(id, headSHA: "e08b5a1")
        let commit = Commit(sha: "3be7d12f0e", subject: "Commit", author: UserRef(login: "lkeller"), authoredAt: .now)
        model.commits = [commit]
        await model.showCommit(commit)
        #expect(model.selectedCommit != nil)
        await model.revealFinding(path: path, line: 10)
        #expect(model.selectedCommit == nil)
        #expect(model.focusedLine?.line == 10)
    }

    @Test func nearestShownLinePrefersTheLowerLineOnATie() {
        let hunk = Hunk(
            oldStart: 1, oldCount: 0, newStart: 1, newCount: 0,
            lines: [
                DiffLine(kind: .added, oldNumber: nil, newNumber: 3, text: "a"),
                DiffLine(kind: .added, oldNumber: nil, newNumber: 7, text: "b"),
            ])
        #expect(DiffScreenModel.nearestShownLine(to: 5, in: [hunk]) == 3)
        #expect(DiffScreenModel.nearestShownLine(to: 6, in: [hunk]) == 7)
        #expect(DiffScreenModel.nearestShownLine(to: 5, in: []) == nil)
    }
}

/// Regression: the AI edge repeated its whole gradient on every line; each row now shows its slice.
struct HighlightSpanTests {
    @Test func positionsALineInTheFindingsRange() {
        let middle = AIHighlightOverlay.span(of: 12, in: 10...14)
        #expect(middle.index == 2 && middle.count == 5)
        #expect(AIHighlightOverlay.span(of: 30, in: 10...14).index == 4)
        let unknown = AIHighlightOverlay.span(of: nil, in: 10...14)
        #expect(unknown.index == 0 && unknown.count == 1)
    }
}
