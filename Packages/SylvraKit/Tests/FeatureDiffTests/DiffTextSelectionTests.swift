import SylvraCore
import Testing

@testable import FeatureDiff

struct DiffTextSelectionTests {
    let hunks = [
        Hunk(
            oldStart: 8, oldCount: 3, newStart: 8, newCount: 3,
            lines: [
                DiffLine(kind: .context, oldNumber: 8, newNumber: 8, text: "func total() {"),
                DiffLine(kind: .removed, oldNumber: 9, newNumber: nil, text: "    old()"),
                DiffLine(kind: .added, oldNumber: nil, newNumber: 9, text: "    new()"),
                DiffLine(kind: .context, oldNumber: 10, newNumber: 10, text: "}"),
            ])
    ]

    private func selection(
        _ lane: DiffSelectionLane, from: (Int, Int), to: (Int, Int)
    ) -> DiffTextSelection {
        DiffTextSelection(
            path: "A.swift", lane: lane,
            anchor: DiffTextPosition(hunk: 0, row: from.0, column: from.1),
            head: DiffTextPosition(hunk: 0, row: to.0, column: to.1))
    }

    @Test func selectsFromAColumnToAColumnAcrossLines() {
        let selected = selection(.inline, from: (0, 5), to: (2, 7))
        #expect(selected.text(in: hunks) == "total() {\n    old()\n    new")
        #expect(selected.location(in: hunks) == CodeLocation(path: "A.swift", line: 9, side: .right, startLine: 8))
    }

    @Test func aBackwardDragSelectsTheSameText() {
        let forward = selection(.inline, from: (0, 5), to: (2, 7))
        let backward = selection(.inline, from: (2, 7), to: (0, 5))
        #expect(backward.text(in: hunks) == forward.text(in: hunks))
    }

    @Test func sideBySideKeepsToOneVersion() {
        // Rows: context, removed | added, context. The left half is the old version.
        let selected = selection(.left, from: (0, 0), to: (2, 1))
        #expect(selected.text(in: hunks) == "func total() {\n    old()\n}")
        #expect(selected.location(in: hunks) == CodeLocation(path: "A.swift", line: 10, side: .left, startLine: 8))
    }

    @Test func columnsBeyondTheLineAreClamped() {
        let selected = selection(.inline, from: (3, 0), to: (3, 40))
        #expect(selected.text(in: hunks) == "}")
        #expect(selected.columns(hunk: 0, row: 3) == 0..<40)
        #expect(selected.columns(hunk: 0, row: 2) == nil)
    }

    @Test func onlyRemovedLinesAreOnTheOldSide() {
        let selected = selection(.inline, from: (1, 0), to: (1, 9))
        #expect(selected.location(in: hunks)?.side == .left)
        #expect(selected.location(in: hunks)?.line == 9)
    }
}

/// Dragging a selection past the top or bottom edge scrolls the diff, faster the further out.
struct DiffAutoscrollTests {
    @Test func scrollsOnlyAtTheEdges() {
        #expect(DiffTextSelectionController.autoscrollSpeed(pointerY: 300, viewHeight: 600) == 0)
        #expect(DiffTextSelectionController.autoscrollSpeed(pointerY: 590, viewHeight: 600) > 0)
        #expect(DiffTextSelectionController.autoscrollSpeed(pointerY: 20, viewHeight: 600) < 0)
    }

    @Test func scrollsFasterFurtherOutUpToALimit() {
        let near = DiffTextSelectionController.autoscrollSpeed(pointerY: 610, viewHeight: 600)
        let far = DiffTextSelectionController.autoscrollSpeed(pointerY: 700, viewHeight: 600)
        let farAbove = DiffTextSelectionController.autoscrollSpeed(pointerY: -400, viewHeight: 600)
        #expect(far > near)
        #expect(far <= 60)
        #expect(farAbove == -60)
    }
}
