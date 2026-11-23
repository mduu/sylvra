import CoreGraphics
import Testing

@testable import FeatureDiff

/// The selection is one outlined shape across its rows, like in an editor.
struct DiffSelectionOutlineTests {
    @Test func aSingleRowIsABox() {
        let outline = DiffSelectionOutline(row: 4..<10, above: nil, below: nil)
        #expect(outline.top == [4..<10])
        #expect(outline.bottom == [4..<10])
        #expect(outline.closesRight)
    }

    @Test func rowsJoinWhereTheyOverlap() {
        // Selected from column 6 of the first row to column 3 of the third.
        let first = DiffSelectionOutline(row: 6..<Int.max, above: nil, below: 0..<Int.max)
        let middle = DiffSelectionOutline(row: 0..<Int.max, above: 6..<Int.max, below: 0..<3)
        let last = DiffSelectionOutline(row: 0..<3, above: 0..<Int.max, below: nil)

        #expect(first.top == [6..<Int.max])
        #expect(first.bottom.isEmpty)
        #expect(!first.closesRight)
        // The middle row's top shows only left of where the first row starts; its bottom right of where the last
        // row ends.
        #expect(middle.top == [0..<6])
        #expect(middle.bottom == [3..<Int.max])
        #expect(last.top.isEmpty)
        #expect(last.bottom == [0..<3])
        #expect(last.closesRight)
    }

    @Test func twoRowsThatDontOverlapAreClosedBoxes() {
        let first = DiffSelectionOutline(row: 8..<Int.max, above: nil, below: 0..<2)
        #expect(first.bottom == [8..<Int.max])
    }

    @Test func subtractingKeepsThePartsOutside() {
        #expect(DiffSelectionOutline.subtract(3..<5, from: 0..<10) == [0..<3, 5..<10])
        #expect(DiffSelectionOutline.subtract(0..<20, from: 2..<10).isEmpty)
        #expect(DiffSelectionOutline.subtract(nil, from: 2..<10) == [2..<10])
        #expect(DiffSelectionOutline.subtract(12..<20, from: 2..<10) == [2..<10])
    }
}

/// ⌘C copies the diff selection, and only when there is one.
@MainActor
struct DiffCopySelectionTests {
    @Test func copiesTheSelectionAndPassesWithoutOne() {
        let controller = DiffTextSelectionController()
        var copied: [DiffTextSelection] = []
        controller.copy = { copied.append($0) }
        #expect(!controller.copySelection())

        let key = DiffTextSelectionController.RowKey(path: "A.swift", lane: .inline, hunk: 0, row: 0)
        controller.register(key, frame: CGRect(x: 100, y: 0, width: 400, height: 22), length: 40)
        controller.drag(from: CGPoint(x: 101, y: 5), to: CGPoint(x: 160, y: 5), horizontalOffset: 0)
        controller.endDrag()
        #expect(controller.copySelection())
        #expect(copied.count == 1)
    }
}
