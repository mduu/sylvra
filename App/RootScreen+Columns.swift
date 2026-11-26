import FeatureAIReview
import FeatureDelivery
import FeatureDiff
import FeatureInbox
import FeaturePullRequest
import FeatureReview
import Observation
import SwiftUI
import SylvraCore

/// The main window, or the second window of the two-window layout (diff and AI).
enum WindowRole {
    case main, review
}

/// State both windows share: the selected pull request and whether the AI inspector is open.
@MainActor @Observable
final class WindowState {
    var selectedID: PullRequestID?
    var isInspectorPresented: Bool

    init(isInspectorPresented: Bool) {
        self.isInspectorPresented = isInspectorPresented
    }
}

// MARK: - Columns

extension RootScreen {
    var selectedID: PullRequestID? {
        get { environment.window.selectedID }
        nonmutating set { environment.window.selectedID = newValue }
    }

    var isInspectorPresented: Bool {
        get { environment.window.isInspectorPresented }
        nonmutating set { environment.window.isInspectorPresented = newValue }
    }

    var selectionBinding: Binding<PullRequestID?> {
        Binding(get: { selectedID }, set: { selectedID = $0 })
    }

    var inspectorBinding: Binding<Bool> {
        Binding(get: { isInspectorPresented }, set: { isInspectorPresented = $0 })
    }

    /// The window's content for its role and layout.
    @ViewBuilder var columns: some View {
        if role == .review {
            reviewColumn
        } else if layout == .twoWindows {
            // Screen one: inbox and the pull request; the diff and AI are in the review window.
            NavigationSplitView(columnVisibility: $columnVisibility) {
                inboxColumn
            } detail: {
                pullRequestScreen
                    .panelHandle(.leading, isVisible: showsInboxHandle) { inboxHandle }
                    .stableColumn()
            }
        } else if layout.stacksInbox || layout.floatsInbox {
            // Compact and focus have no inbox column: compact lists the inbox in the pull request column, focus
            // floats it in on demand. A hidden inbox sidebar didn't stay hidden (window restoration showed it
            // again), and the inbox was there twice.
            NavigationSplitView(columnVisibility: $columnVisibility) {
                pullRequestColumn
                    .panelHandle(.leading, isVisible: showsInboxHandle) { inboxHandle }
                    .toolbar(removing: .sidebarToggle)
                    .rememberedColumn(.pullRequest, ideal: pullRequestWidth)
                    .navigationSplitViewColumnWidth(
                        min: ColumnLayout.Column.pullRequest.range.lowerBound, ideal: pullRequestWidth,
                        max: ColumnLayout.Column.pullRequest.range.upperBound)
            } detail: {
                reviewColumn
            }
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                inboxColumn
            } content: {
                pullRequestColumn
                    .panelHandle(.leading, isVisible: showsInboxHandle) { inboxHandle }
                    .rememberedColumn(.pullRequest, ideal: pullRequestWidth)
                    .navigationSplitViewColumnWidth(
                        min: ColumnLayout.Column.pullRequest.range.lowerBound, ideal: pullRequestWidth,
                        max: ColumnLayout.Column.pullRequest.range.upperBound)
            } detail: {
                reviewColumn
            }
        }
    }

    var inboxColumn: some View {
        InboxScreen(model: environment.inbox, selection: selectionBinding)
            // The inbox is toggled with the handle on its edge (⌘0), in every layout.
            .panelHandle(.trailing, isVisible: showsHandleInInbox) { inboxHandle }
            .toolbar(removing: .sidebarToggle)
            .rememberedColumn(.inbox, ideal: inboxWidth)
            .navigationSplitViewColumnWidth(
                min: ColumnLayout.Column.inbox.range.lowerBound, ideal: inboxWidth,
                max: ColumnLayout.Column.inbox.range.upperBound)
    }

    /// The pull request, or in the compact layout the inbox in its place (`StackedInboxColumn`).
    @ViewBuilder var pullRequestColumn: some View {
        if layout.stacksInbox {
            StackedInboxColumn(
                listsInbox: listsInboxInColumn, canGoBack: selection != nil,
                showInbox: { withAnimation(.snappy) { isInboxListed = true } },
                inbox: { InboxScreen(model: environment.inbox, selection: stackedSelection) },
                pullRequest: { pullRequestScreen })
        } else {
            pullRequestScreen
        }
    }

    /// Picking a pull request in the stacked inbox opens it, also the one that is already open. The list
    /// shows no selection for that reason: clicking an already selected row reports nothing.
    private var stackedSelection: Binding<PullRequestID?> {
        Binding(
            get: { nil },
            set: { id in
                guard let id else { return }
                withAnimation(.snappy) {
                    selectedID = id
                    isInboxListed = false
                }
            })
    }

    var pullRequestScreen: some View {
        PullRequestScreen(
            model: environment.pullRequest, pullRequest: selection,
            selectedCommitSHA: environment.diff.selectedCommit?.sha,
            selectCommit: { commit in Task { await environment.diff.showCommit(commit) } },
            showInCode: { path, line in Task { await environment.diff.reveal(path, line: line) } },
            openPullRequest: { pullRequest in
                environment.inbox.remember(pullRequest)
                selectedID = pullRequest.id
            },
            refreshOthers: {
                // Everything else shown for the pull request: comments, code threads, new commits, the inbox.
                async let conversation: Void = environment.conversation.refresh()
                async let threads: Void = environment.review.refreshThreads()
                async let commits: Void = environment.diff.checkForNewCommits()
                async let inbox: Void = environment.inbox.refresh()
                _ = await (conversation, threads, commits, inbox)
            },
            delivery: AnyView(
                DeliveryPanel(
                    model: environment.delivery, pullRequestID: selection?.id, askAI: { askAI($0) },
                    openSession: { openClaudeSession($0) })),
            shareSummary: { selection.flatMap { environment.aiReview.results[$0.id]?.summary } },
            summary: {
                AISummaryPanel(model: environment.aiReview, pullRequestID: selection?.id) { path in
                    Task { await environment.diff.reveal(path) }
                }
            },
            overviewTop: { ChangeMapPanel(model: environment.diff) },
            files: {
                DiffFileNavigatorPanel(model: environment.diff) { item in
                    NavigatorToolsMenu(environment: environment, item: item, pullRequest: selection?.id)
                }
            },
            conversation: {
                ConversationPanel(model: environment.conversation, pullRequestID: selection?.id) {
                    guard let id = selection?.id else { return }
                    Task { await environment.pullRequest.load(id) }
                }
            }
        )
    }

    var reviewColumn: some View {
        ReviewScreen(model: environment.review, pullRequestID: selection?.id) {
            DiffScreen(
                model: environment.diff,
                pullRequestID: selection?.id,
                headSHA: environment.pullRequest.detail.flatMap {
                    $0.summary.id == selection?.id ? $0.headSHA : nil
                },
                lineAccessory: { lineAccessory(at: $0) },
                onStartComment: { environment.review.startComment(at: $0, lineText: $1) },
                onAskAI: { location, code in askAI(about: location, code: code) },
                openInIDE: selection.map { pullRequest in
                    DiffOpenInIDE(
                        name: environment.openInIDE.preferredIDE(for: pullRequest.id).name,
                        context: pullRequest.id.description
                    ) { path, line in
                        Task { await environment.openInIDE.open(pullRequest.id, file: path, line: line) }
                    }
                },
                onRefresh: {
                    guard let id = selection?.id else { return }
                    await environment.pullRequest.load(id)
                    await environment.inbox.refresh()
                },
                // A comment being written keeps its lines; the banner then offers Refresh.
                refreshesAutomatically: { environment.review.draft == nil }
            )
            .environment(\.diffTrailingCover, floatingInspectorInset)
            .animation(.snappy, value: floatingInspectorInset)
            .closesFloatingPanel(inspectorBinding, isEnabled: !layout.docksInspector && isInspectorPresented)
        }
        .panelHandle(.trailing, isVisible: hasAIPanel && !isInspectorPresented) { aiHandle }
        .terminalPanel(environment, selection: selection, isEnabled: hostsBottomPanel)
        .stableColumn()
    }

    /// Only one window shows the terminal: each session has a single AppKit view, and a second
    /// (even hidden) window rendering the panel takes it away, leaving the visible terminal blank.
    /// The review window exists in the background in every layout, so the main window is the host
    /// unless the two-window layout puts the diff in the review window.
    var hostsBottomPanel: Bool {
        let isTwoWindows = WindowLayout(rawValue: layoutMode) == .twoWindows
        return role == (isTwoWindows ? .review : .main)
    }
}
