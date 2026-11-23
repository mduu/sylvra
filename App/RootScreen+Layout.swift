import FeatureAIReview
import FeatureDiff
import FeatureInbox
import FeaturePullRequest
import SwiftUI
import SylvraCore

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
            useAsComment: { answer, location in useAsComment(answer, at: location) },
            showPullRequest: showPullRequest
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
            .onChange(of: root.displays.setup) {
                // The columns are rebuilt for the new screens: they start with the layout's columns again.
                Task { @MainActor in root.columnVisibility = root.layout.columnVisibility }
            }
            .overlay(alignment: .leading) { floatingInbox(layout) }
            .overlay(alignment: .trailing) { floatingInspector(layout) }
            .animation(.snappy, value: root.isInboxFloating)
            .animation(.snappy, value: root.isInspectorPresented)
            .toolbar { layoutToolbar(layout) }
    }
}

extension WindowLayoutModifier {
    /// Focus: the inbox floats in from the left, its handle inside on the panel's trailing edge.
    @ViewBuilder
    fileprivate func floatingInbox(_ layout: WindowLayout) -> some View {
        if layout.floatsInbox, root.isInboxFloating, root.role == .main {
            // The handle sits inside the panel on its trailing edge, like the AI handle in the floating inspector.
            FloatingPanel(edge: .leading, width: 300, isPresented: root.$isInboxFloating) {
                InboxScreen(model: root.environment.inbox, selection: root.selectionBinding)
            } handle: {
                root.inboxHandle
            }
            .transition(.move(edge: .leading).combined(with: .opacity))
        }
    }

    /// Compact: the AI panel floats in from the right, its handle inside on the panel's left edge.
    @ViewBuilder
    fileprivate func floatingInspector(_ layout: WindowLayout) -> some View {
        if !layout.docksInspector, root.isInspectorPresented {
            // The handle sits inside the panel on its left edge, not floating beside it over the diff.
            FloatingPanel(
                edge: .trailing, width: WindowLayout.floatingInspectorWidth, isPresented: root.inspectorBinding
            ) {
                root.inspectorContent
            } handle: {
                root.aiHandle
            }
            .transition(.move(edge: .trailing).combined(with: .opacity))
        }
    }

    /// Files (the review window, which has no pull request column) or the review window button (two windows);
    /// the layout menu is in `mainToolbar`. The inbox and the AI panel are toggled with the handles on their
    /// edges (`PanelHandles`).
    @ToolbarContentBuilder
    fileprivate func layoutToolbar(_ layout: WindowLayout) -> some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if root.role == .review {
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

    /// Compact: a click into the diff puts the floating AI panel away, since it covers the diff's right side
    /// (on a laptop much of the right half of a side-by-side diff). Taken on mouse-down, so a click that
    /// opens the panel again on mouse-up (✦ on a finding, *Ask in chat*) still wins.
    func closesFloatingPanel(_ isPresented: Binding<Bool>, isEnabled: Bool) -> some View {
        simultaneousGesture(
            DragGesture(minimumDistance: 0).onChanged { _ in
                guard isPresented.wrappedValue else { return }
                withAnimation(.snappy) { isPresented.wrappedValue = false }
            },
            including: isEnabled ? .all : .subviews)
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

extension RootScreen {
    /// Opens a pull request with its AI inspector (from the activity list or a review running elsewhere).
    func showPullRequest(_ id: PullRequestID) {
        withAnimation(.snappy) {
            selectedID = id
            isInboxListed = false
            isInspectorPresented = true
        }
    }
}
