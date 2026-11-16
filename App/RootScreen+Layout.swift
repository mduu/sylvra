import FeatureAIReview
import FeatureDiff
import FeatureInbox
import SwiftUI

// MARK: - Window layouts (wide, compact, focus)

extension RootScreen {
    /// The AI inspector as a sidebar (wide and focus layouts); compact floats it instead.
    var dockedInspector: Binding<Bool> {
        Binding(
            get: { isInspectorPresented && layout.docksInspector },
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

    func body(content: Content) -> some View {
        let layout = root.layout
        content
            .onGeometryChange(for: Bool.self) {
                $0.size.width < WindowLayout.compactBelow
            } action: { isNarrow in
                // A Bool, not the width: resizing only re-renders when the automatic layout flips.
                if root.isNarrowWindow != isNarrow { root.isNarrowWindow = isNarrow }
            }
            .onChange(of: layout, initial: true) { _, layout in
                withAnimation(.snappy) {
                    root.columnVisibility = layout.columnVisibility
                    if layout != .compact { root.isInboxFloating = false }
                }
            }
            .onChange(of: root.selectedID) {
                // Picking a pull request from the floating inbox closes it.
                withAnimation(.snappy) { root.isInboxFloating = false }
            }
            .overlay(alignment: .leading) {
                if layout == .compact, root.isInboxFloating {
                    FloatingPanel(edge: .leading, width: 300, isPresented: root.$isInboxFloating) {
                        InboxScreen(model: root.environment.inbox, selection: root.$selectedID)
                    }
                }
            }
            .overlay(alignment: .trailing) {
                if !layout.docksInspector, root.isInspectorPresented {
                    FloatingPanel(edge: .trailing, width: 360, isPresented: root.$isInspectorPresented) {
                        root.inspectorContent
                    }
                }
            }
            .animation(.snappy, value: root.isInboxFloating)
            .animation(.snappy, value: root.isInspectorPresented)
            .toolbar {
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
                    }
                }
                ToolbarItem(placement: .primaryAction) {
                    WindowLayoutMenu(selection: root.$layoutMode, resolved: layout)
                }
            }
    }
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
