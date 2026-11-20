import Foundation
import Testing

@testable import Platform

@Suite struct DisplaySetupTests {
    private let laptop = DisplaySetup.Display(name: "Built-in Retina Display", width: 1512, height: 982)
    private let wide = DisplaySetup.Display(name: "LG HDR WQHD", width: 3440, height: 1440)

    private func memory() -> (DisplayLayoutMemory, UserDefaults) {
        let defaults = UserDefaults(suiteName: "DisplaySetupTests-\(UUID().uuidString)")!
        return (DisplayLayoutMemory(defaults: defaults), defaults)
    }

    @Test func theOrderOfTheScreensDoesNotMatter() {
        #expect(DisplaySetup(displays: [laptop, wide]) == DisplaySetup(displays: [wide, laptop]))
        #expect(DisplaySetup(displays: [laptop, wide]).key == DisplaySetup(displays: [wide, laptop]).key)
    }

    @Test func twoEqualScreensDifferFromOne() {
        let one = DisplaySetup(displays: [wide])
        let two = DisplaySetup(displays: [wide, wide])
        #expect(one != two)
        #expect(one.key != two.key)
    }

    @Test func remembersValuesPerSetup() {
        let (memory, _) = memory()
        let office = DisplaySetup(displays: [laptop, wide])
        let mobile = DisplaySetup(displays: [laptop])
        memory.setNumber(400, "columnWidth.inbox", for: office)
        memory.setNumber(240, "columnWidth.inbox", for: mobile)
        memory.setText("wide", "mode", for: office)
        memory.setText("compact", "mode", for: mobile)

        #expect(memory.number("columnWidth.inbox", for: office) == 400)
        #expect(memory.number("columnWidth.inbox", for: mobile) == 240)
        #expect(memory.text("mode", for: office) == "wide")
        #expect(memory.text("mode", for: mobile) == "compact")
    }

    @Test func aNewSetupStartsWithTheLastWidthsButNoMode() {
        let (memory, _) = memory()
        memory.setNumber(333, "columnWidth.inbox", for: DisplaySetup(displays: [wide]))
        let new = DisplaySetup(displays: [wide, wide])
        #expect(memory.number("columnWidth.inbox", for: new) == 333)
        #expect(memory.text("mode", for: new) == nil)
    }

    @Test func readsTheWidthsSavedBeforeTheyWerePerSetup() {
        let (memory, defaults) = memory()
        defaults.set(310.0, forKey: "layout.columnWidth.pullRequest")
        #expect(memory.number("columnWidth.pullRequest", for: DisplaySetup(displays: [laptop])) == 310)
    }
}
