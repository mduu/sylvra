import AppKit
import Testing

@testable import DesignSystem

struct DesignSystemTests {
    @Test func aiTextSizesGrowAndStartAtTheSystemSize() {
        let scales = AITextSize.allCases.map(\.scale)
        #expect(scales.first == 1)
        #expect(scales == scales.sorted())
        #expect(AITextSize(rawValue: "unknown") == nil)
    }

    @Test func aiFontsUseTheMacOSTextStyleSizes() {
        #expect(AIFontMetrics.pointSize(of: .callout) == 12)
        #expect(AIFontMetrics.pointSize(of: .caption) == 10)
        #expect(AIFontMetrics.pointSize(of: .body) == 13)
    }
}

@MainActor
struct ToolbarSymbolCacheTests {
    /// Regression: a new image per view update looped the window's constraint pass (crash at launch).
    @Test func returnsTheSameImageForTheSameSymbol() throws {
        let first = try #require(ToolbarSymbolCache.image("terminal", leading: 9))
        let second = try #require(ToolbarSymbolCache.image("terminal", leading: 9))
        #expect(first === second)
        #expect(first.isTemplate)
        #expect(ToolbarSymbolCache.image("not-a-symbol-name", leading: 9) == nil)
    }
}
