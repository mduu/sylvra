import Testing

@testable import SylvraCore

struct CodeLocationTests {
    @Test func dropsStartLineForSingleLines() {
        let single = CodeLocation(path: "a.swift", line: 4, side: .right, startLine: 4)
        #expect(single.startLine == nil)
        #expect(single.lines == 4...4)
    }

    @Test func coversRanges() {
        let range = CodeLocation(path: "a.swift", line: 9, side: .left, startLine: 7)
        #expect(range.lines == 7...9)
        #expect(range.anchor == CodeLocation(path: "a.swift", line: 9, side: .left))
        #expect(range.description == "a.swift:7–9")
    }
}
