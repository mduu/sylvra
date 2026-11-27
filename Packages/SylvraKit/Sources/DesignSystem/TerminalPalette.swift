/// The 16 ANSI colors of the terminal, tuned for its dark violet background (`SylvraColor.terminalBackground`,
/// dark in both appearances, so one palette serves both). xterm's defaults are too dark there: blue and dark grey
/// were hard to read. Every color but black stays readable on both backgrounds (see the contrast tests).
public enum TerminalPalette {
    /// Black, red, green, yellow, blue, magenta, cyan, white, then their bright variants, as `0xRRGGBB`.
    public static let ansi: [UInt32] = [
        0x2A_1F45, 0xFF_6B81, 0x5F_D38D, 0xF2_C94C, 0x6E_A8FF, 0xD0_8CFF, 0x4F_D6E0, 0xD9_D2EE,
        0x8A_7FA8, 0xFF_8FA0, 0x8B_E9A8, 0xFF_E08A, 0x9C_C3FF, 0xE5_B3FF, 0x8E_EBF2, 0xFF_FFFF,
    ]

    /// The terminal backgrounds the palette is checked against (light and dark appearance).
    public static let backgrounds: [UInt32] = [0x1F_1240, 0x0B_051A]

    /// A color's channels in 0…255.
    public struct Components: Equatable, Sendable {
        public let red: UInt16
        public let green: UInt16
        public let blue: UInt16
    }

    public static func components(_ color: UInt32) -> Components {
        Components(red: UInt16((color >> 16) & 0xFF), green: UInt16((color >> 8) & 0xFF), blue: UInt16(color & 0xFF))
    }
}
