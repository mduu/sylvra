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
