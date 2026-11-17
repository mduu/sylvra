import AppKit

/// Double-clicking empty space in the title bar or toolbar zooms the window (or minimizes it, following
/// System Settings), like everywhere on macOS. SwiftUI's window content reaches under the toolbar and
/// swallows those clicks, so only the strip around the traffic lights reacted.
@MainActor
final class TitlebarDoubleClick {
    static let shared = TitlebarDoubleClick()
    private var monitor: Any?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .leftMouseDown) { event in
            guard event.clickCount == 2, let window = event.window,
                Self.isEmptyTitlebarSpace(at: event.locationInWindow, in: window)
            else { return event }
            Self.performDoubleClickAction(on: window)
            return nil
        }
    }

    /// Inside the title bar / toolbar strip and not on a control or a SwiftUI toolbar item.
    static func isEmptyTitlebarSpace(at point: NSPoint, in window: NSWindow) -> Bool {
        guard window.styleMask.contains(.titled), point.y >= window.contentLayoutRect.maxY,
            let frameView = window.contentView?.superview,
            let hit = frameView.hitTest(frameView.convert(point, from: nil))
        else { return false }
        var view: NSView? = hit
        while let current = view, current !== frameView {
            if current is NSControl || isInteractive(current) { return false }
            view = current.superview
        }
        return true
    }

    /// Toolbar items and other clickable SwiftUI content (buttons, the title chips) handle clicks themselves.
    private static func isInteractive(_ view: NSView) -> Bool {
        let name = String(describing: type(of: view))
        return name.contains("ToolbarItemViewer") || name.contains("PlatformViewHost") || name.contains("Button")
            || name.contains("ToolbarItemHosting")
    }

    /// Follows System Settings › Desktop & Dock › "Double-click a window's title bar to".
    static func performDoubleClickAction(on window: NSWindow) {
        switch UserDefaults.standard.string(forKey: "AppleActionOnDoubleClick") {
        case "Minimize": window.performMiniaturize(nil)
        case "None": break
        default: window.performZoom(nil)
        }
    }
}
