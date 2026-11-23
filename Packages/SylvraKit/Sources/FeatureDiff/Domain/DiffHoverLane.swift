import CoreGraphics

/// Which row lane the pointer is over, from the code frames rows register for mouse selection. A lane reaches
/// left over its gutter up to the lane before it, so hovering a line number counts for that line.
enum DiffHoverLane {
    typealias RowKey = DiffTextSelectionController.RowKey

    /// The gutter in front of a right half's code, with some slack: a right half without a left one beside it
    /// (hatched, no code) must not take the pointer over that empty left half.
    static let gutterReach: CGFloat = halfGutterWidth + 16

    @MainActor
    static func lane(at point: CGPoint, in lanes: [(key: RowKey, frame: CGRect)]) -> RowKey? {
        let row = lanes.filter { $0.frame.minY <= point.y && point.y < $0.frame.maxY }
            .sorted { $0.frame.minX < $1.frame.minX }
        for index in row.indices.reversed() {
            let lane = row[index]
            let start: CGFloat =
                if index > 0 {
                    row[index - 1].frame.maxX
                } else {
                    lane.key.lane == .right ? lane.frame.minX - gutterReach : -.infinity
                }
            if point.x >= start, point.x <= lane.frame.maxX + connectorWidth { return lane.key }
        }
        return nil
    }
}
