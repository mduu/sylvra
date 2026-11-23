import DesignSystem
import SwiftUI

// MARK: - Collapse / expand handles for the inbox and the AI panel

/// One handle per side panel on its edge: the inbox handle collapses the inbox column or floats the inbox in
/// (focus); the AI handle shows or hides the inspector, docked or floating. In the compact layout the inbox has
/// no handle: it shares the pull request column (`‹ Inbox` goes back, ⌘0 switches).
extension RootScreen {
    /// The inbox is visible in this window.
    var isInboxShown: Bool {
        if layout.stacksInbox { return listsInboxInColumn }
        return layout.floatsInbox ? isInboxFloating : columnVisibility == .all
    }

    /// Compact: the pull request column shows the inbox (also while no pull request is selected).
    var listsInboxInColumn: Bool {
        layout.stacksInbox && (isInboxListed || selection == nil)
    }

    func toggleInbox() {
        guard role == .main else { return }
        withAnimation(.snappy) {
            if layout.stacksInbox {
                isInboxListed = !listsInboxInColumn
            } else if layout.floatsInbox {
                isInboxFloating.toggle()
            } else if isInboxShown {
                columnVisibility = layout == .twoWindows ? .detailOnly : .doubleColumn
            } else {
                columnVisibility = .all
            }
        }
    }

    /// The window can show the AI panel (in the two-window layout it lives in the review window).
    var hasAIPanel: Bool { !(role == .main && layout == .twoWindows) }

    /// Open: inside the inbox on its trailing edge (like the AI handle inside the AI panel). Closed: on the
    /// leading edge of the column the inbox would push aside.
    var inboxHandle: some View {
        PanelEdgeHandle(
            attachedTo: isInboxShown ? .trailing : .leading, pointsTo: isInboxShown ? .leading : .trailing,
            help: isInboxShown ? "Hide the inbox (⌘0)" : "Show the inbox (⌘0)",
            // A closed inbox is easy to lose; the brand color makes its way back stand out.
            isProminent: !isInboxShown, action: toggleInbox)
    }

    /// Closed: on the diff's trailing edge. Open: on the AI panel's leading edge.
    var aiHandle: some View {
        let isOpen = isInspectorPresented
        return PanelEdgeHandle(
            attachedTo: isOpen ? .leading : .trailing, pointsTo: isOpen ? .trailing : .leading,
            help: isOpen ? "Hide the AI panel (⌥⌘I)" : "Show the AI panel (⌥⌘I)"
        ) {
            withAnimation(.snappy) { isInspectorPresented.toggle() }
        }
    }

    /// Where the closed inbox handle sits: the pull request column, or the diff in the focus layout. The open
    /// inbox carries its handle itself (`showsHandleInInbox`, the floating inbox).
    func showsInboxHandle(onReviewColumn: Bool) -> Bool {
        guard role == .main, !layout.stacksInbox, !isInboxShown else { return false }
        return onReviewColumn == (layout == .focus)
    }

    /// The docked inbox column is open: its handle sits inside it.
    var showsHandleInInbox: Bool {
        role == .main && !layout.stacksInbox && !layout.floatsInbox && isInboxShown
    }
}

extension View {
    /// Places a panel handle vertically centered on one edge.
    func panelHandle(_ edge: HorizontalEdge, isVisible: Bool, @ViewBuilder handle: () -> some View) -> some View {
        overlay(alignment: edge == .leading ? .leading : .trailing) {
            if isVisible {
                handle().transition(.opacity)
            }
        }
    }
}
