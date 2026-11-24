import AppKit
import FeatureAIReview
import FeatureActivity
import FeatureDiff
import FeatureOpenInIDE
import FeaturePullRequest
import FeatureReview
import FeatureUpdates
import SwiftUI

/// The window toolbar: the pull request info in the middle; on the left what decides which code you see and
/// how (refresh, changes, commits, diff layout, window layout), on the right what you do with the pull request
/// (open in IDE and terminal as one group, AI review, submit review), then the activity. The side panels have
/// handles on their edges.
extension RootScreen {
    @ToolbarContentBuilder var mainToolbar: some ToolbarContent {
        DiffToolbar(model: environment.diff)
        // How the window is arranged, next to how the diff is shown.
        ToolbarItem(placement: .navigation) {
            WindowLayoutMenu(selection: $layoutMode, resolved: layout)
        }
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
        // Working on the checkout: IDE / tools and terminals share one group.
        ToolbarItem(placement: .primaryAction) {
            // One toolbar item, so both menus sit in one glass capsule.
            HStack(spacing: 0) {
                OpenInIDEToolbarPanel(model: environment.openInIDE, pullRequestID: selection?.id)
                TerminalToolbarMenu(environment: environment, pullRequest: selection?.id)
            }
        }
        ToolbarItem(placement: .primaryAction) {
            AIReviewToolbarPanel(
                model: environment.aiReview, pullRequest: selection,
                pullRequestBody: environment.pullRequest.detail?.body ?? "")
        }
        .sharedBackgroundVisibility(.hidden)
        ToolbarItem(placement: .primaryAction) {
            SubmitReviewToolbarButton(model: environment.review, pullRequestID: selection?.id)
        }
        ToolbarSpacer(.fixed, placement: .primaryAction)
        if role == .main, environment.updates.pendingRelease != nil, !environment.updates.isCardPresented {
            ToolbarItem(placement: .primaryAction) {
                UpdateToolbarButton(model: environment.updates)
            }
            // Its own capsule: not part of the pull request actions.
            ToolbarSpacer(.fixed, placement: .primaryAction)
        }
        ToolbarItem(placement: .primaryAction) {
            ActivityToolbarPanel(center: environment.activity, open: showPullRequest)
        }
    }
}
