import DesignSystem
import SwiftUI

/// Compact layout: inbox and pull request share one column (container). The inbox is the top level; a picked
/// pull request opens in its place, and `‹ Inbox` at the top left goes back (⌘0 switches as well).
struct StackedInboxColumn<Inbox: View, PullRequest: View>: View {
    let listsInbox: Bool
    /// A pull request is open to go back to.
    let canGoBack: Bool
    let showInbox: () -> Void
    @ViewBuilder let inbox: Inbox
    @ViewBuilder let pullRequest: PullRequest
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if listsInbox {
                inbox
                    .background(SylvraColor.surfaceSidebar)
                    .transition(transition(from: .leading))
            } else {
                VStack(alignment: .leading, spacing: 0) {
                    if canGoBack { backBar }
                    pullRequest
                }
                .transition(transition(from: .trailing))
            }
        }
        .clipped()
    }

    private var backBar: some View {
        BackButton("Inbox", action: showInbox)
            .help("Back to the inbox (⌘0)")
            .padding(.horizontal, 12)
            .padding(.top, 6)
            .frame(maxWidth: .infinity, alignment: .leading)
            .background(SylvraColor.surfacePrimary)
    }

    /// A push like a navigation stack; a cross-fade with Reduce Motion.
    private func transition(from edge: Edge) -> AnyTransition {
        reduceMotion ? .opacity : .move(edge: edge).combined(with: .opacity)
    }
}

#Preview("Stacked inbox column") {
    @Previewable @State var listsInbox = false
    StackedInboxColumn(
        listsInbox: listsInbox, canGoBack: true, showInbox: { withAnimation(.snappy) { listsInbox = true } },
        inbox: {
            List(["#1234 Add intra-line diff", "#1240 Fix scroll jump"], id: \.self) { title in
                Button(title) { withAnimation(.snappy) { listsInbox = false } }.buttonStyle(.plain)
            }
        },
        pullRequest: { Text("Pull request").frame(maxWidth: .infinity, maxHeight: .infinity) }
    )
    .frame(width: 380, height: 400)
}
