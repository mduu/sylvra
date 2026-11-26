import AppKit

/// A picture of one of Sylvra's own windows, drawn by the app itself: it cannot show other apps and needs no
/// screen recording permission.
@MainActor
public enum WindowSnapshot {
    /// The window the user works in: the key or main window, never a panel or the given window to skip (the
    /// feedback window itself).
    public static func workingWindow(excluding skipped: NSWindow? = nil) -> NSWindow? {
        let candidates = [NSApp.mainWindow, NSApp.keyWindow] + NSApp.orderedWindows.map { Optional($0) }
        return candidates.compactMap { $0 }.first { window in
            window !== skipped && window.isVisible && !(window is NSPanel) && window.styleMask.contains(.titled)
                && window.identifier?.rawValue.contains(skippedIdentifier) != true
        }
    }

    /// Windows with this in their identifier are never captured (the feedback window).
    public static let skippedIdentifier = "feedback"

    /// PNG data of the window with its title bar and toolbar (`nil`: nothing to draw).
    public static func png(of window: NSWindow) -> Data? {
        // The frame view holds the title bar and the content.
        guard let view = window.contentView?.superview ?? window.contentView,
            let bitmap = view.bitmapImageRepForCachingDisplay(in: view.bounds)
        else { return nil }
        view.cacheDisplay(in: view.bounds, to: bitmap)
        return bitmap.representation(using: .png, properties: [:])
    }
}
