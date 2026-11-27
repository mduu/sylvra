import Foundation
import Testing

@testable import DesignSystem

struct TerminalPaletteTests {
    private func luminance(_ color: UInt32) -> Double {
        let parts = TerminalPalette.components(color)
        func linear(_ value: UInt16) -> Double {
            let channel = Double(value) / 255
            return channel <= 0.03928 ? channel / 12.92 : pow((channel + 0.055) / 1.055, 2.4)
        }
        return 0.2126 * linear(parts.red) + 0.7152 * linear(parts.green) + 0.0722 * linear(parts.blue)
    }

    private func contrast(_ first: UInt32, _ second: UInt32) -> Double {
        let (light, dark) = (max(luminance(first), luminance(second)), min(luminance(first), luminance(second)))
        return (light + 0.05) / (dark + 0.05)
    }

    @Test func sixteenColors() {
        #expect(TerminalPalette.ansi.count == 16)
    }

    /// WCAG AA for text (4.5) for every color, 3 for bright black (dim text, like comments); black is a fill.
    @Test func readableOnBothBackgrounds() {
        for background in TerminalPalette.backgrounds {
            for (index, color) in TerminalPalette.ansi.enumerated() where index != 0 {
                let needed = index == 8 ? 3.0 : 4.5
                #expect(contrast(color, background) >= needed, "color \(index) on \(String(background, radix: 16))")
            }
        }
    }

    /// Black must still be told apart from the background (as a fill, e.g. a status bar).
    @Test func blackDiffersFromTheBackground() {
        for background in TerminalPalette.backgrounds {
            #expect(TerminalPalette.ansi[0] != background)
        }
    }
}
