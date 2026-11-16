import FeatureAIReview
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
                pullRequestScreen.stableColumn()
            }
        } else {
            NavigationSplitView(columnVisibility: $columnVisibility) {
                inboxColumn
            } content: {
                pullRequestScreen
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
            .rememberedColumn(.inbox, ideal: inboxWidth)
            .navigationSplitViewColumnWidth(
                min: ColumnLayout.Column.inbox.range.lowerBound, ideal: inboxWidth,
                max: ColumnLayout.Column.inbox.range.upperBound)
    }

    var pullRequestScreen: some View {
        PullRequestScreen(
            model: environment.pullRequest, pullRequest: selection,
            selectedCommitSHA: environment.diff.selectedCommit?.sha,
            selectCommit: { commit in Task { await environment.diff.showCommit(commit) } },
            showInCode: { path, line in Task { await environment.diff.reveal(path, line: line) } },
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
                onRefresh: {
                    guard let id = selection?.id else { return }
                    await environment.pullRequest.load(id)
                    await environment.inbox.refresh()
                }
            )
        }
        .terminalPanel(environment, selection: selection)
        .stableColumn()
    }
}
