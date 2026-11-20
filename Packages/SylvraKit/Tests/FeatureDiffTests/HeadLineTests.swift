import Testing

@testable import FeatureDiff

@Suite struct HeadLineTests {
    private let hunk = Hunk(
        oldStart: 10, oldCount: 4, newStart: 10, newCount: 3,
        lines: [
            DiffLine(kind: .context, oldNumber: 10, newNumber: 10, text: "a"),
            DiffLine(kind: .removed, oldNumber: 11, newNumber: nil, text: "b"),
            DiffLine(kind: .removed, oldNumber: 12, newNumber: nil, text: "c"),
            DiffLine(kind: .added, oldNumber: nil, newNumber: 11, text: "B"),
            DiffLine(kind: .context, oldNumber: 13, newNumber: 12, text: "d"),
        ])

    @Test func newAndContextLinesOpenAtTheirOwnLine() {
        #expect(hunk.headLine(for: hunk.lines[0]) == 10)
        #expect(hunk.headLine(for: hunk.lines[3]) == 11)
    }

    @Test func removedLinesOpenAtTheNextLineThatStillExists() {
        #expect(hunk.headLine(for: hunk.lines[1]) == 11)
        #expect(hunk.headLine(for: hunk.lines[2]) == 11)
    }

    @Test func removedLinesAtTheEndOpenAtThePreviousLine() {
        let tail = Hunk(
            oldStart: 5, oldCount: 2, newStart: 5, newCount: 1,
            lines: [
                DiffLine(kind: .context, oldNumber: 5, newNumber: 5, text: "x"),
                DiffLine(kind: .removed, oldNumber: 6, newNumber: nil, text: "y"),
            ])
        #expect(tail.headLine(for: tail.lines[1]) == 5)
    }

    @Test func aDeletedFileOpensAtItsStart() {
        let deleted = Hunk(
            oldStart: 1, oldCount: 1, newStart: 0, newCount: 0,
            lines: [DiffLine(kind: .removed, oldNumber: 1, newNumber: nil, text: "gone")])
        #expect(deleted.headLine(for: deleted.lines[0]) == 1)
    }
}
