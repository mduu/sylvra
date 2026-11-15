import AppKit
import SwiftUI

/// Brand color tokens derived from the app icon (see specs/ux.md §3.1).
public enum SylvraColor {
    /// Primary brand color: key actions, active states.
    public static let brandPrimary = dynamic(light: 0x6C48C6, dark: 0xB39AF2)
    /// Secondary surfaces, selected rows, subtle fills.
    public static let brandSecondary = dynamic(light: 0xB39AF2, dark: 0x4B2A8A)
    /// Very light tints, hover backgrounds, empty states.
    public static let brandTint = dynamic(light: 0xEADFFF, dark: 0x2D1857)
    /// Accent for the focus of attention (use sparingly).
    public static let accentGold = dynamic(light: 0xE2B44F, dark: 0xF7DC86)
    /// Gold glow and specular highlights.
    public static let accentGoldSoft = dynamic(light: 0xFFF1BF, dark: 0xFFF1BF)
    /// Brand backgrounds (splash, empty states, onboarding).
    public static let canvasDeep = dynamic(light: 0x170A33, dark: 0x0B051A)
    /// Terminal background: dark violet in both appearances (slightly lifted in light mode).
    public static let terminalBackground = dynamic(light: 0x1F1240, dark: 0x0B051A)
    /// Terminal text on `terminalBackground`.
    public static let terminalForeground = dynamic(light: 0xF1ECFF, dark: 0xE4DCF7)
    /// Terminal text selection.
    public static let terminalSelection = dynamic(light: 0x4B2A8A, dark: 0x3A2270)

    private static func dynamic(light: UInt32, dark: UInt32) -> Color {
        Color(
            nsColor: NSColor(name: nil) { appearance in
                let isDark = appearance.bestMatch(from: [.darkAqua, .aqua]) == .darkAqua
                return NSColor(hex: isDark ? dark : light)
            }
        )
    }
}

extension NSColor {
    fileprivate convenience init(hex: UInt32) {
        self.init(
            srgbRed: CGFloat((hex >> 16) & 0xFF) / 255,
            green: CGFloat((hex >> 8) & 0xFF) / 255,
            blue: CGFloat(hex & 0xFF) / 255,
            alpha: 1
        )
    }
}
