import AppKit
import Foundation

/// Errors when opening an external terminal.
public enum ExternalTerminalError: LocalizedError, Equatable {
    case notInstalled(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let bundleIdentifier):
            String(localized: "No app with bundle identifier \(bundleIdentifier) is installed.")
        }
    }
}

/// Opens a folder in a terminal app via `NSWorkspace` (Terminal, iTerm2, Ghostty, Warp all accept folders).
public struct ExternalTerminalLauncher: ExternalTerminalOpening {
    public init() {}

    public func open(_ directory: URL, bundleIdentifier: String) async throws {
        guard let app = NSWorkspace.shared.urlForApplication(withBundleIdentifier: bundleIdentifier) else {
            throw ExternalTerminalError.notInstalled(bundleIdentifier)
        }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.open([directory], withApplicationAt: app, configuration: configuration)
    }
}
