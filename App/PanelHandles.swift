import DesignSystem
import SwiftUI

// MARK: - Collapse / expand handles for the inbox and the AI panel

/// One handle per side panel on its edge, in every layout: the inbox handle collapses the inbox column or
/// floats the inbox in (compact, focus); the AI handle shows or hides the inspector, docked or floating.
extension RootScreen {
    /// The inbox is visible in this window.
    var isInboxShown: Bool {
        layout.floatsInbox ? isInboxFloating : columnVisibility == .all
    }

    func toggleInbox() {
        guard role == .main else { return }
        withAnimation(.snappy) {
            if layout.floatsInbox {
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

    /// On the leading edge of the column right of the inbox (or of the floating inbox).
    var inboxHandle: some View {
        PanelEdgeHandle(
            attachedTo: .leading, pointsTo: isInboxShown ? .leading : .trailing,
            help: isInboxShown ? "Hide the inbox (⌘0)" : "Show the inbox (⌘0)", action: toggleInbox)
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

    /// Where the closed inbox handle sits: the pull request column, or the diff in the focus layout.
    func showsInboxHandle(onReviewColumn: Bool) -> Bool {
        guard role == .main, !(layout.floatsInbox && isInboxFloating) else { return false }
        return onReviewColumn == (layout == .focus)
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
