import FeatureAIReview
import FeatureDiff
import FeatureInbox
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
            .onChange(of: layout, initial: true) { _, layout in
                withAnimation(.snappy) {
                    root.columnVisibility = layout.columnVisibility
                    if layout != .compact { root.isInboxFloating = false }
                }
                guard root.role == .main else { return }
                if layout == .twoWindows {
                    openWindow(id: RootScreen.reviewWindowID)
                } else {
                    dismissWindow(id: RootScreen.reviewWindowID)
                }
            }
            .onChange(of: root.selectedID) {
                // Picking a pull request from the floating inbox closes it.
                withAnimation(.snappy) { root.isInboxFloating = false }
            }
            .overlay(alignment: .leading) {
                if layout == .compact, root.isInboxFloating {
                    FloatingPanel(edge: .leading, width: 300, isPresented: root.$isInboxFloating) {
                        InboxScreen(model: root.environment.inbox, selection: root.selectionBinding)
                    }
                }
            }
            .overlay(alignment: .trailing) {
                if !layout.docksInspector, root.isInspectorPresented {
                    FloatingPanel(edge: .trailing, width: 360, isPresented: root.inspectorBinding) {
                        root.inspectorContent
                    }
                }
            }
            .animation(.snappy, value: root.isInboxFloating)
            .animation(.snappy, value: root.isInspectorPresented)
            .toolbar { layoutToolbar(layout) }
    }
}

extension WindowLayoutModifier {
    /// Inbox button (compact), files (focus) or review window (two windows); the layout menu is in `mainToolbar`.
    @ToolbarContentBuilder
    fileprivate func layoutToolbar(_ layout: WindowLayout) -> some ToolbarContent {
        ToolbarItem(placement: .navigation) {
            if layout == .compact {
                Button {
                    root.isInboxFloating.toggle()
                } label: {
                    Label("Inbox", systemImage: "tray")
                }
                .help("Show the inbox (⌘0)")
                .keyboardShortcut("0", modifiers: .command)
            } else if layout == .focus {
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
