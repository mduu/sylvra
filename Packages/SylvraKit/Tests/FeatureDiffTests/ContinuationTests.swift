import Foundation
import Testing

@testable import FeatureDiff

struct ContinuationTests {
    private func line(_ kind: DiffLine.Kind, _ number: Int = 1) -> DiffLine {
        DiffLine(
            kind: kind, oldNumber: kind == .added ? nil : number, newNumber: kind == .removed ? nil : number, text: "x")
    }

    @Test func ribbonContinuesInsideEqualBlocks() {
        // 3 removed ↔ 3 added: full width between all rows, nothing after the last.
        let segment = { ConnectorSegment(indexInBlock: $0, blockRows: 3, leftRows: 3, rightRows: 3) }
        #expect(segment(0).crossSection(rowHeight: 22) == 0...1)
        #expect(segment(1).crossSection(rowHeight: 22) == 0...1)
        #expect(segment(2).crossSection(rowHeight: 22) == nil)
    }

    @Test func ribbonNarrowsTowardsTheTallerSide() throws {
        // 1 removed ↔ 4 added (screenshot case): below row 1 only the right part of the band continues.
        let below = try #require(
            ConnectorSegment(indexInBlock: 1, blockRows: 4, leftRows: 1, rightRows: 4).crossSection(rowHeight: 22))
        #expect(below.upperBound == 1)
        #expect(below.lowerBound > 0.2 && below.lowerBound < 0.9)
        let lower = try #require(
            ConnectorSegment(indexInBlock: 2, blockRows: 4, leftRows: 1, rightRows: 4).crossSection(rowHeight: 22))
        #expect(lower.lowerBound > below.lowerBound)
        // Mirrored: more removed lines keep the left part.
        let mirrored = try #require(
            ConnectorSegment(indexInBlock: 1, blockRows: 4, leftRows: 4, rightRows: 1).crossSection(rowHeight: 22))
        #expect(mirrored.lowerBound == 0)
        #expect(abs(mirrored.upperBound - (1 - below.lowerBound)) < 0.01)
    }

    @Test func halvesContinueBarsAndHatching() {
        #expect(HalfContinuation.between(line(.added), and: line(.added), hasNext: true) == .changeBar(.added))
        #expect(HalfContinuation.between(line(.added), and: line(.context), hasNext: true) == .none)
        #expect(HalfContinuation.between(line(.context), and: line(.context), hasNext: true) == .none)
        #expect(HalfContinuation.between(nil, and: nil, hasNext: true) == .empty)
        #expect(HalfContinuation.between(nil, and: nil, hasNext: false) == .none)
        #expect(HalfContinuation.between(line(.removed), and: nil, hasNext: true) == .none)
    }
}

/// Regression: with the floating AI panel open in the compact layout, a thread in the narrow right half of a
/// side-by-side diff kept clear of the whole panel and was squeezed to a few letters per line.
struct TrailingClearanceTests {
    @Test func keepsClearOfThePanelOnlyWhileTheBoxStaysWide() {
        #expect(trailingClearance(cover: 376, width: 1000, minimum: 420) == 376)
        #expect(trailingClearance(cover: 376, width: 600, minimum: 420) == 180)
        #expect(trailingClearance(cover: 376, width: 380, minimum: 420) == 0)
        #expect(trailingClearance(cover: 0, width: 1000, minimum: 420) == 0)
    }

    /// Regression: selecting an AI finding in the compact layout hung the app. The lane measured its own width
    /// and fed it back as padding; a card wider than the minimum grew the lane, which grew the padding, round
    /// after round. The inset now comes from the offered width alone, in one layout pass.
    @Test func laneInsetDependsOnlyOnTheOfferedWidth() {
        let lane = TrailingClearanceLayout(leading: 16, cover: 376, minimum: 420, excluded: 16)
        #expect(lane.inset(forWidth: 1016) == 392)  // gutter + whole cover
        #expect(lane.inset(forWidth: 616) == 196)  // gutter + what keeps 420 pt
        #expect(lane.inset(forWidth: 300) == 16)
        // Ideal sizing (nil or infinite) never adds a clearance.
        #expect(lane.inset(forWidth: nil) == 16)
        #expect(lane.inset(forWidth: .infinity) == 16)

        let box = TrailingClearanceLayout(leading: 4, trailing: 4, cover: 376, minimum: 240)
        #expect(box.inset(forWidth: 400) == 168)  // paddings + what keeps 240 pt
        #expect(TrailingClearanceLayout(leading: 4, trailing: 4, cover: 0, minimum: 240).inset(forWidth: 900) == 8)
    }
}
