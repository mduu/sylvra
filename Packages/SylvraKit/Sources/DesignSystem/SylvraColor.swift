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

    // MARK: Window surfaces (from the design preview)

    /// Main content background (PR column, window).
    public static let surfacePrimary = dynamic(light: 0xFBFAFE, dark: 0x120A26)
    /// Sidebar and inspector.
    public static let surfaceSidebar = dynamic(light: 0xF5F2FC, dark: 0x140B2A)
    /// Cards and elevated panels on a surface.
    public static let surfaceElevated = dynamic(light: 0xFFFFFF, dark: 0x1C1236)
    /// Selected rows (inbox selection, file selection).
    public static let surfaceSelected = dynamic(light: 0xECE4FB, dark: 0x2A1B4E)

    // MARK: Diff surface

    /// Background of code in the diff (a calm, slightly violet canvas).
    public static let codeSurface = dynamic(light: 0xFFFFFF, dark: 0x130B26)
    /// Gutter behind line numbers.
    public static let codeGutter = dynamic(light: 0xF6F3FC, dark: 0x0F0820)
    /// Hairlines inside the diff.
    public static let codeHairline = dynamic(light: 0xE6E0F2, dark: 0x2A1F45)
    /// Added lines (fresh teal-green, harmonizes with violet).
    public static let diffAdded = dynamic(light: 0x1E9E6A, dark: 0x4BD39A)
    /// Removed lines (soft coral).
    public static let diffRemoved = dynamic(light: 0xD8435E, dark: 0xF2738A)

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
