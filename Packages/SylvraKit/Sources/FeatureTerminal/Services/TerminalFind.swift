import AppKit
@preconcurrency import SwiftTerm

/// ⌘F while a terminal has the keyboard focus searches the terminal (SwiftTerm's find bar) instead of the diff.
@MainActor
public enum TerminalFind {
    /// Shows the focused terminal's find bar; `false` when no terminal has the focus.
    public static func showIfFocused() -> Bool {
        guard let view = NSApp.keyWindow?.firstResponder as? TerminalView else { return false }
        let item = NSMenuItem()
        item.tag = NSTextFinder.Action.showFindInterface.rawValue
        view.performTextFinderAction(item)
        return true
    }
}
