import AppKit

/// Single-key shortcuts for reviewing (`j`/`k`, `n`/`p`, `v`, `?` …), like GitHub and other review tools.
/// Keys pass through while text is edited (comment composer, chat, search, terminal) or with ⌘ / ⌃ / ⌥.
@MainActor
final class KeyboardNavigator {
    private var monitor: Any?
    /// Returns `true` when the key was handled.
    var handler: ((String) -> Bool)?

    func start() {
        guard monitor == nil else { return }
        monitor = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { [weak self] event in
            guard Self.isPlainKey(event), let key = event.charactersIgnoringModifiers else { return event }
            // Local monitors run on the main thread.
            let handled = MainActor.assumeIsolated {
                guard let self, !Self.isTyping(in: NSApp.keyWindow) else { return false }
                return self.handler?(key) == true
            }
            return handled ? nil : event
        }
    }

    func stop() {
        if let monitor { NSEvent.removeMonitor(monitor) }
        monitor = nil
    }

    private nonisolated static func isPlainKey(_ event: NSEvent) -> Bool {
        event.modifierFlags.isDisjoint(with: [.command, .control, .option])
    }

    /// Text fields, editors and the terminal keep their keys.
    private static func isTyping(in window: NSWindow?) -> Bool {
        guard let window, window.attachedSheet == nil else { return true }
        guard let responder = window.firstResponder else { return false }
        if responder is NSText { return true }
        return String(describing: type(of: responder)).contains("Terminal")
    }
}
