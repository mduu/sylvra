import CoreGraphics
import Testing

@testable import FeatureTerminal

@Suite struct TerminalWheelTests {
    @Test func scrollbackOnTheNormalScreen() {
        #expect(TerminalWheelAction(lines: 3, mouseReporting: false, alternateScreen: false) == .scrollback(lines: 3))
        #expect(TerminalWheelAction(lines: -2, mouseReporting: false, alternateScreen: false) == .scrollback(lines: -2))
    }

    @Test func arrowKeysForAFullScreenProgram() {
        #expect(
            TerminalWheelAction(lines: -2, mouseReporting: false, alternateScreen: true)
                == .arrowKeys(up: false, count: 2))
    }

    @Test func wheelEventsWhenTheProgramWantsTheMouse() {
        #expect(
            TerminalWheelAction(lines: 1, mouseReporting: true, alternateScreen: true)
                == .mouseWheel(up: true, count: 1))
    }

    @Test func nothingForLessThanALine() {
        #expect(TerminalWheelAction(lines: 0, mouseReporting: false, alternateScreen: false) == nil)
    }

    @Test func smoothSwipesAddUpToLines() {
        var wheel = TerminalWheelAccumulator()
        #expect(wheel.lines(for: 6, precise: true, lineHeight: 16) == 0)
        #expect(wheel.lines(for: 6, precise: true, lineHeight: 16) == 0)
        #expect(wheel.lines(for: 6, precise: true, lineHeight: 16) == 1)
        #expect(wheel.lines(for: 40, precise: true, lineHeight: 16) == 2)
    }

    @Test func aNewDirectionStartsAfresh() {
        var wheel = TerminalWheelAccumulator()
        _ = wheel.lines(for: 14, precise: true, lineHeight: 16)
        #expect(wheel.lines(for: -10, precise: true, lineHeight: 16) == 0)
        #expect(wheel.lines(for: -10, precise: true, lineHeight: 16) == -1)
    }

    @Test func mouseWheelDeltasAreLines() {
        var wheel = TerminalWheelAccumulator()
        #expect(wheel.lines(for: 3, precise: false, lineHeight: 16) == 3)
    }
}
