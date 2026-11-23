/// One row's part of the outline drawn around a selection: the filled columns and which edges carry the border,
/// so the rows together form one shape like an editor selection (first row from its column to the right edge,
/// full rows in between, the last row up to its column). Columns use `Int.max` for "to the right edge".
struct DiffSelectionOutline: Equatable {
    /// Filled columns of this row.
    var fill: Range<Int>
    /// Columns whose top edge is part of the outline (not covered by the row above).
    var top: [Range<Int>]
    /// Columns whose bottom edge is part of the outline (not covered by the row below).
    var bottom: [Range<Int>]
    /// The right end is a real edge (the selection ends in this row); otherwise it runs to the right edge.
    var closesRight: Bool { fill.upperBound != Int.max }

    /// - Parameters:
    ///   - row: this row's selected columns.
    ///   - above: the selected columns of the row directly above (`nil`: none, a hunk header, another hunk).
    ///   - below: the same for the row directly below.
    init(row: Range<Int>, above: Range<Int>?, below: Range<Int>?) {
        fill = row
        top = Self.subtract(above, from: row)
        bottom = Self.subtract(below, from: row)
    }

    /// The parts of `range` that `other` doesn't cover.
    static func subtract(_ other: Range<Int>?, from range: Range<Int>) -> [Range<Int>] {
        guard let other, other.overlaps(range) else { return range.isEmpty ? [] : [range] }
        var parts: [Range<Int>] = []
        if other.lowerBound > range.lowerBound { parts.append(range.lowerBound..<other.lowerBound) }
        if other.upperBound < range.upperBound { parts.append(other.upperBound..<range.upperBound) }
        return parts
    }
}
