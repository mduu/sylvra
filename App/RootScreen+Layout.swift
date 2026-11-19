import FeatureAIReview
import FeatureDiff
import FeatureInbox
import FeaturePullRequest
import SwiftUI

// MARK: - Window layouts (wide, compact, focus)

extension RootScreen {
    /// The AI inspector as a sidebar (wide and focus layouts); compact floats it instead.
    var dockedInspector: Binding<Bool> {
        Binding(
            // Two windows: the AI lives in the review window, not next to the inbox.
            get: { isInspectorPresented && layout.docksInspector && !(role == .main && layout == .twoWindows) },
            set: { isInspectorPresented = $0 })
    }

    /// Room kept free at the trailing edge of boxes inside the diff (comment composer, threads, findings), so
    /// the floating AI panel does not cover their text and buttons.
    var floatingInspectorInset: CGFloat {
        !layout.docksInspector && isInspectorPresented ? WindowLayout.floatingInspectorCover : 0
    }

    var inspectorContent: some View {
        FindingsInspectorScreen(
            model: environment.aiReview,
            pullRequest: selection,
            pullRequestBody: environment.pullRequest.detail?.body ?? "",
            jump: { finding in jump(to: finding) },
            turnIntoComment: { finding in startComment(from: finding) },
            chat: environment.chat,
            jumpToLocation: { path, line in Task { await environment.diff.reveal(path, line: line) } },
            useAsComment: { answer, location in useAsComment(answer, at: location) }
        )
    }
}

/// Applies the chosen layout: column visibility, floating inbox and inspector, layout toolbar items.
private struct WindowLayoutModifier: ViewModifier {
    let root: RootScreen
    @Environment(\.openWindow) private var openWindow
    @Environment(\.dismissWindow) private var dismissWindow

    func body(content: Content) -> some View {
        let layout = root.layout
        content
            .onGeometryChange(for: WindowLayout.WidthBand.self) {
                // A band, not the width: resizing only reports something when a threshold is crossed.
                WindowLayout.WidthBand(width: $0.size.width)
            } action: { band in
                let isNarrow = band.isNarrow(wasNarrow: root.isNarrowWindow)
                guard root.isNarrowWindow != isNarrow else { return }
                // After the current layout pass: flipping the columns inside AppKit's constraint pass can
                // make it loop (crash in _postWindowNeedsUpdateConstraints on windows near the threshold).
                Task { @MainActor in root.isNarrowWindow = isNarrow }
            }
            .onGeometryChange(for: Int.self) {
                // 20 pt steps: the box only needs to know roughly how wide the window is.
                Int($0.size.width / 20)
            } action: { step in
                let width = PullRequestTitleView.width(
                    forWindowWidth: CGFloat(step) * 20, current: root.titleBoxWidth)
                guard width != root.titleBoxWidth else { return }
                // After the current layout pass, like the layout switch above.
                Task { @MainActor in root.titleBoxWidth = width }
            }
            .onChange(of: layout, initial: true) { _, layout in
                withAnimation(.snappy) {
                    root.columnVisibility = layout.columnVisibility
                    root.isInboxFloating = false
                    root.isInboxListed = false
                }
                guard root.role == .main else { return }
                if layout == .twoWindows {
                    openWindow(id: RootScreen.reviewWindowID)
                } else {
                    dismissWindow(id: RootScreen.reviewWindowID)
                }
            }
            .onChange(of: root.selectedID) {
                // Picking a pull request (inbox, notification) closes the floating inbox and shows the pull request.
                withAnimation(.snappy) {
                    root.isInboxFloating = false
                    root.isInboxListed = false
                }
            }
            .overlay(alignment: .leading) { floatingInbox(layout) }
            .overlay(alignment: .trailing) { floatingInspector(layout) }
            .animation(.snappy, value: root.isInboxFloating)
            .animation(.snappy, value: root.isInspectorPresented)
            .toolbar { layoutToolbar(layout) }
    }
}

extension WindowLayoutModifier {
    /// Focus: the inbox floats in from the left, its handle on the panel's edge.
    @ViewBuilder
    fileprivate func floatingInbox(_ layout: WindowLayout) -> some View {
        if layout.floatsInbox, root.isInboxFloating, root.role == .main {
            // The handle rides on the panel's edge (the panel's padding is the negative spacing).
            HStack(spacing: -8) {
                FloatingPanel(edge: .leading, width: 300, isPresented: root.$isInboxFloating) {
                    InboxScreen(model: root.environment.inbox, selection: root.selectionBinding)
                }
                root.inboxHandle
            }
            .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }

    /// Compact: the AI panel floats in from the right, its handle on the panel's edge.
    @ViewBuilder
    fileprivate func floatingInspector(_ layout: WindowLayout) -> some View {
        if !layout.docksInspector, root.isInspectorPresented {
            HStack(spacing: -8) {
                root.aiHandle
                FloatingPanel(
                    edge: .trailing, width: WindowLayout.floatingInspectorWidth, isPresented: root.inspectorBinding
                ) {
                    root.inspectorContent
                }
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    /// Files (focus) or review window (two windows); the layout menu is in `mainToolbar`. The inbox and the
    /// AI panel are toggled with the handles on their edges (`PanelHandles`).
    @ToolbarContentBuilder
    fileprivate func layoutToolbar(_ layout: WindowLayout) -> some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if layout == .focus {
                FocusFilesButton(model: root.environment.diff)
            } else if layout == .twoWindows {
                Button {
                    openWindow(id: RootScreen.reviewWindowID)
                } label: {
                    Label("Review window", systemImage: "macwindow.on.rectangle")
                }
                .help("Bring the review window (diff and AI) to the front")
            }
        }
    }
}

extension RootScreen {
    static let reviewWindowID = "review"
}

extension View {
    func windowLayout(_ root: RootScreen) -> some View {
        modifier(WindowLayoutModifier(root: root))
    }
}

/// Focus layout: the changed files in a popover (the pull request column is hidden).
private struct FocusFilesButton: View {
    let model: DiffScreenModel
    @State private var isPresented = false

    var body: some View {
        Button {
            isPresented.toggle()
        } label: {
            Label("Files", systemImage: "list.bullet.indent")
        }
        .help("Changed files")
        .popover(isPresented: $isPresented, arrowEdge: .bottom) {
            ScrollView {
                DiffFileNavigatorPanel(model: model) { _ in EmptyView() }
                    .padding(12)
            }
            .frame(width: 340, height: 460)
        }
        .onChange(of: model.selectedPath) { isPresented = false }
    }
}
