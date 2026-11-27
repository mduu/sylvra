import Foundation

/// A terminal app that can open a folder ("Open in external terminal").
public struct ExternalTerminal: Identifiable, Hashable, Sendable {
    public var id: String { bundleIdentifier }
    public let name: String
    public let bundleIdentifier: String

    public init(name: String, bundleIdentifier: String) {
        self.name = name
        self.bundleIdentifier = bundleIdentifier
    }

    public static let terminal = ExternalTerminal(name: "Terminal", bundleIdentifier: "com.apple.Terminal")
    public static let presets: [ExternalTerminal] = [
        .terminal,
        ExternalTerminal(name: "iTerm2", bundleIdentifier: "com.googlecode.iterm2"),
        ExternalTerminal(name: "Ghostty", bundleIdentifier: "com.mitchellh.ghostty"),
        ExternalTerminal(name: "Warp", bundleIdentifier: "dev.warp.Warp-Stable"),
    ]

    /// The preset with `bundleIdentifier`, or a custom entry named after it.
    public static func named(_ bundleIdentifier: String) -> ExternalTerminal {
        presets.first { $0.bundleIdentifier == bundleIdentifier }
            ?? ExternalTerminal(name: bundleIdentifier, bundleIdentifier: bundleIdentifier)
    }
}

/// UserDefaults keys of the terminal settings (shared by the model and the settings pane).
public enum TerminalPreferences {
    /// Shell path; empty = the user's login shell.
    public static let shellKey = "terminal.shell"
    /// Bundle identifier of the external terminal app; empty = Terminal.
    public static let externalTerminalKey = "terminal.externalApp"
    /// Whether the left Option key is Meta (⌥B → ESC b) instead of typing the layout's characters. Off by default:
    /// on Swiss and German keyboards ⌥ types `~ @ [ ] { } |`. Arrows, Backspace and Enter are Meta with either.
    public static let leftOptionIsMetaKey = "terminal.leftOptionIsMeta"
    /// Font size of the terminal panel in points.
    public static let fontSizeKey = "terminal.fontSize"
    public static let defaultFontSize: Double = 13
    public static let fontSizes: ClosedRange<Double> = 9...24

    /// A stored font size within `fontSizes` (0 or garbage falls back to the default).
    public static func fontSize(_ stored: Double) -> Double {
        guard stored > 0 else { return defaultFontSize }
        return min(max(stored.rounded(), fontSizes.lowerBound), fontSizes.upperBound)
    }
}
