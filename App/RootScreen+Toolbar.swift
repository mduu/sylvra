import AppKit
import FeatureAIReview
import FeatureActivity
import FeatureDiff
import FeatureOpenInIDE
import FeaturePullRequest
import FeatureReview
import SwiftUI

/// The window toolbar: the pull request info in the middle; on the left what decides which code you see and
/// how (sidebar, refresh, changes, commits, diff layout), on the right what you do with the pull request
/// (open in IDE, terminal, AI review, submit review), then the window controls (activity, layout, AI panel).
extension RootScreen {
    @ToolbarContentBuilder var mainToolbar: some ToolbarContent {
        DiffToolbar(model: environment.diff)
        ToolbarItem(placement: .principal) {
            PullRequestTitleView(
                pullRequest: selection,
                detail: environment.pullRequest.detail,
                width: titleBoxWidth,
                open: { NSWorkspace.shared.open($0) },
                showTab: { environment.pullRequest.tab = $0 },
                doubleClick: {
                    guard let window = NSApp.keyWindow else { return }
                    TitlebarDoubleClick.performDoubleClickAction(on: window)
                })
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .primaryAction) {
            OpenInIDEToolbarPanel(model: environment.openInIDE, pullRequestID: selection?.id)
        }
        ToolbarItem(placement: .primaryAction) {
            TerminalToolbarMenu(environment: environment, pullRequest: selection?.id)
        }
        ToolbarItem(placement: .primaryAction) {
            AIReviewToolbarPanel(
                model: environment.aiReview, pullRequest: selection,
                pullRequestBody: environment.pullRequest.detail?.body ?? "")
        }
        ToolbarItem(placement: .primaryAction) {
            SubmitReviewToolbarButton(model: environment.review, pullRequestID: selection?.id)
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        ToolbarItem(placement: .primaryAction) {
            ActivityToolbarPanel(center: environment.activity)
        }
        ToolbarItem(placement: .primaryAction) {
            WindowLayoutMenu(selection: $layoutMode, resolved: layout)
        }
        ToolbarItem(placement: .primaryAction) {
            Button {
                isInspectorPresented.toggle()
            } label: {
                Label("AI Inspector", systemImage: "sidebar.right")
            }
            .help("Show or hide the AI panel")
        }
    }
}
