import CoreGraphics
import Testing

@testable import FeatureDiff

/// The diff tracks the pointer once and maps it to the row lane under it.
@MainActor
struct DiffHoverTests {
    typealias Key = DiffTextSelectionController.RowKey

    static func key(_ lane: DiffSelectionLane, row: Int = 0) -> Key {
        Key(path: "A.swift", lane: lane, hunk: 0, row: row)
    }

    /// A side-by-side row 0 (y 0–22) in a 1000 pt wide diff: code from 92 to 478 and from 614 to 1000.
    let sideBySide: [(key: Key, frame: CGRect)] = [
        (key(.left), CGRect(x: 92, y: 0, width: 386, height: 22)),
        (key(.right), CGRect(x: 614, y: 0, width: 386, height: 22)),
        (key(.left, row: 1), CGRect(x: 92, y: 22, width: 386, height: 22)),
    ]

    @Test func theGutterBelongsToItsLine() {
        #expect(DiffHoverLane.lane(at: CGPoint(x: 10, y: 5), in: sideBySide) == Self.key(.left))
        #expect(DiffHoverLane.lane(at: CGPoint(x: 300, y: 5), in: sideBySide) == Self.key(.left))
        // The right half's gutter starts where the left half's code ends.
        #expect(DiffHoverLane.lane(at: CGPoint(x: 540, y: 5), in: sideBySide) == Self.key(.right))
        #expect(DiffHoverLane.lane(at: CGPoint(x: 900, y: 5), in: sideBySide) == Self.key(.right))
        #expect(DiffHoverLane.lane(at: CGPoint(x: 10, y: 30), in: sideBySide) == Self.key(.left, row: 1))
    }

    @Test func emptyHalvesAndGapsHoverNothing() {
        // Row 1 has no right half (hatched): its right side is no line.
        #expect(DiffHoverLane.lane(at: CGPoint(x: 800, y: 30), in: sideBySide) == nil)
        // A lone right half doesn't reach over the empty left half.
        let loneRight = [(key: Self.key(.right), frame: CGRect(x: 614, y: 0, width: 386, height: 22))]
        #expect(DiffHoverLane.lane(at: CGPoint(x: 100, y: 5), in: loneRight) == nil)
        // Between rows (a review thread, a hunk header).
        #expect(DiffHoverLane.lane(at: CGPoint(x: 100, y: 60), in: sideBySide) == nil)
    }

    @Test func onlyTheLanesThatChangeAreTouched() {
        let controller = DiffTextSelectionController()
        for lane in sideBySide { controller.register(lane.key, frame: lane.frame, length: 40) }
        let left = controller.hoverFlag(for: Self.key(.left))
        let right = controller.hoverFlag(for: Self.key(.right))

        controller.hover(at: CGPoint(x: 10, y: 5))
        #expect(left.isHovered && !right.isHovered)
        controller.hover(at: CGPoint(x: 900, y: 5))
        #expect(!left.isHovered && right.isHovered)
        controller.hover(at: nil)
        #expect(!left.isHovered && !right.isHovered)
    }

    @Test func scrollingMovesTheHoverWithTheContent() {
        let controller = DiffTextSelectionController()
        for lane in sideBySide { controller.register(lane.key, frame: lane.frame, length: 40) }
        controller.hover(at: CGPoint(x: 10, y: 5))
        // The diff scrolls one row down under the resting pointer.
        controller.visibleRect = CGRect(x: 0, y: 22, width: 1000, height: 600)
        #expect(controller.hoverFlag(for: Self.key(.left, row: 1)).isHovered)
        #expect(!controller.hoverFlag(for: Self.key(.left)).isHovered)
    }
}
