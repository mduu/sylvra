import SwiftUI

/// Auto / Light / Dark (see specs/ux.md §3.2). Stored under `appearance` in UserDefaults.
public enum AppearanceSetting: String, CaseIterable, Identifiable, Sendable {
    case auto, light, dark

    public static let storageKey = "appearance"

    public var id: String { rawValue }

    public var title: LocalizedStringKey {
        switch self {
        case .auto: "Automatic"
        case .light: "Light"
        case .dark: "Dark"
        }
    }

    /// `nil` follows the system.
    public var colorScheme: ColorScheme? {
        switch self {
        case .auto: nil
        case .light: .light
        case .dark: .dark
        }
    }
}
