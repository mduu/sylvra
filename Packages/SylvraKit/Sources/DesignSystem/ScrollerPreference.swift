import Foundation

/// Sylvra uses overlay scroll bars unless the user chose "Always" in System Settings.
///
/// With a mouse attached, "Automatically" gives legacy scroll bars that take ~15 pt of width. They come
/// and go with the content height and the window's focus, so the columns' content got narrower and wider
/// (truncated text jumped, e.g. while an AI review added rows).
public enum ScrollerPreference {
    static let key = "AppleShowScrollBars"

    /// The value to use for this app, or `nil` to keep the system setting.
    static func override(forGlobal global: String?) -> String? {
        global == "Always" ? nil : "WhenScrolling"
    }

    /// Applies the override for this launch only (argument domain, never written to disk).
    public static func apply(defaults: UserDefaults = .standard) {
        let global = defaults.persistentDomain(forName: UserDefaults.globalDomain)?[key] as? String
        guard let value = override(forGlobal: global) else { return }
        var arguments = defaults.volatileDomain(forName: UserDefaults.argumentDomain)
        arguments[key] = value
        defaults.setVolatileDomain(arguments, forName: UserDefaults.argumentDomain)
    }
}
