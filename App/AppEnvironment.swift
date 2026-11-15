import FeatureAIReview
import FeatureActivity
import FeatureDiff
import FeatureInbox
import FeatureOpenInIDE
import FeaturePullRequest
import Foundation
import Platform

/// Composition root: creates the services and feature models of the app.
///
/// Launch arguments (used for demos and screenshots):
/// - `--demo`: fixture data instead of GitHub
/// - `--select owner/repo#number`: select that PR once the inbox is loaded
/// - `--tab overview|commits|checks`: initial tab of the PR column
/// - `--layout inline`: inline instead of side-by-side diff
/// - `--focus`: hide the inbox sidebar; `--no-inspector`: hide the AI inspector
/// - `--run-ai-review`: start an AI review as soon as a PR is selected
@MainActor
final class AppEnvironment {
    let isDemo: Bool
    let initialSelection: String?
    let startsFocused: Bool
    let showsInspector: Bool
    let autoRunsAIReview: Bool
    let gitHub: GitHubClient
    let inbox: InboxScreenModel
    let pullRequest: PullRequestScreenModel
    let diff: DiffScreenModel
    let openInIDE: OpenInIDEModel
    let aiReview: AIReviewModel
    let activity = ActivityCenter()

    init(arguments: [String] = CommandLine.arguments) {
        isDemo = arguments.contains("--demo")
        initialSelection = Self.value(of: "--select", in: arguments)
        startsFocused = arguments.contains("--focus")
        showsInspector = !arguments.contains("--no-inspector")
        autoRunsAIReview = arguments.contains("--run-ai-review")
        gitHub = GitHubClient(tokenProvider: GitHubCLITokenProvider())
        let inboxLoader: any InboxLoading = isDemo ? DemoInboxLoader() : GitHubInboxLoader(client: gitHub)
        inbox = InboxScreenModel(loader: inboxLoader)
        let detailLoader: any PullRequestDetailLoading =
            isDemo ? DemoPullRequestDetailLoader() : GitHubPullRequestDetailLoader(client: gitHub)
        pullRequest = PullRequestScreenModel(loader: detailLoader)
        openInIDE =
            isDemo
            ? OpenInIDEModel(checkout: DemoCheckout(), opener: DemoIDEOpener())
            : OpenInIDEModel(checkout: CheckoutService(), opener: IDELauncher())
        let diffLoader: any DiffLoading = isDemo ? DemoDiffLoader() : GitHubDiffLoader(client: gitHub)
        diff = DiffScreenModel(loader: diffLoader)
        let checkout: (any CheckoutPreparing)? = isDemo ? nil : CheckoutService()
        aiReview = AIReviewModel(
            engine: ReviewEngine(provider: isDemo ? DemoAgentProvider() : ClaudeCodeProvider()),
            files: { id in ReviewableFiles.make(from: try await diffLoader.loadDiff(for: id).files) },
            workspace: { id in try await checkout?.prepareWorktree(for: id) }
        )
        if Self.value(of: "--layout", in: arguments) == "inline" { diff.layout = .inline }
        if let tab = Self.value(of: "--tab", in: arguments).flatMap(PullRequestScreenModel.Tab.init(rawValue:)) {
            pullRequest.tab = tab
        }
    }

    private static func value(of flag: String, in arguments: [String]) -> String? {
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }
}
