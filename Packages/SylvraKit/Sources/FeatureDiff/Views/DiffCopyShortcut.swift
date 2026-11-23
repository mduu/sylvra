import AppKit
import SwiftUI

/// ⌘C copies the code selected in the diff. Diff rows aren't text views, so nothing in the responder chain
/// answers *Copy*; a local key monitor takes ⌘C while there is a diff selection. Text being edited, or text
/// selected elsewhere (the chat, a comment), keeps its own ⌘C.
struct DiffCopyShortcut: ViewModifier {
    /// Copies the diff selection; `false` when there is none (the key then goes on as usual).
    let copy: () -> Bool
    @State private var monitor = CopyKeyMonitor()

    func body(content: Content) -> some View {
        content
            .onAppear { monitor.start(copy) }
            .onDisappear { monitor.stop() }
    }
}

extension View {
    func diffCopyShortcut(_ copy: @escaping () -> Bool) -> some View {
        modifier(DiffCopyShortcut(copy: copy))
    }
}

/// Holds the event monitor (reference type: the closure must outlive view updates).
@MainActor
private final class CopyKeyMonitor {
    private var token: Any?

    func start(_ copy: @escaping () -> Bool) {
        stop()
        token = NSEvent.addLocalMonitorForEvents(matching: .keyDown) { event in
            guard Self.isCopyKey(event) else { return event }
            // Local monitors run on the main thread.
            let copied = MainActor.assumeIsolated {
                !Self.textHasTheCopy(in: event.window ?? NSApp.keyWindow) && copy()
            }
            return copied ? nil : event
        }
    }

    func stop() {
        if let token { NSEvent.removeMonitor(token) }
        token = nil
    }

    private nonisolated static func isCopyKey(_ event: NSEvent) -> Bool {
        event.modifierFlags.intersection(.deviceIndependentFlagsMask) == .command
            && event.charactersIgnoringModifiers?.lowercased() == "c"
    }

    /// A text field being edited, or text selected in a text view (chat answers, descriptions), copies itself.
    private static func textHasTheCopy(in window: NSWindow?) -> Bool {
        guard let window, window.attachedSheet == nil else { return true }
        guard let textView = window.firstResponder as? NSTextView else {
            return String(describing: type(of: window.firstResponder)).contains("Terminal")
        }
        return textView.isEditable || textView.selectedRange().length > 0
    }
}
