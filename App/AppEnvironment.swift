import FeatureDiff
import FeatureInbox
import FeaturePullRequest
import FeatureReview
import Foundation
import Platform
import SylvraCore

/// Composition root: creates the services and feature models of the app.
///
/// Launch arguments (used for demos and screenshots):
/// - `--demo`: fixture data instead of GitHub
/// - `--select owner/repo#number`: select that PR once the inbox is loaded
/// - `--tab overview|commits|checks`: initial tab of the PR column
/// - `--layout inline`: inline instead of side-by-side diff
/// - `--focus`: hide the inbox sidebar; `--no-inspector`: hide the AI inspector
/// - `--submit-review`: open the submit review sheet; `--compose path:line`: open the comment composer
@MainActor
final class AppEnvironment {
    let isDemo: Bool
    let initialSelection: String?
    let startsFocused: Bool
    let showsInspector: Bool
    let gitHub: GitHubClient
    let inbox: InboxScreenModel
    let pullRequest: PullRequestScreenModel
    let diff: DiffScreenModel
    let review: ReviewScreenModel

    init(arguments: [String] = CommandLine.arguments) {
        isDemo = arguments.contains("--demo")
        initialSelection = Self.value(of: "--select", in: arguments)
        startsFocused = arguments.contains("--focus")
        showsInspector = !arguments.contains("--no-inspector")
        gitHub = GitHubClient(tokenProvider: GitHubCLITokenProvider())
        let inboxLoader: any InboxLoading = isDemo ? DemoInboxLoader() : GitHubInboxLoader(client: gitHub)
        inbox = InboxScreenModel(loader: inboxLoader)
        let detailLoader: any PullRequestDetailLoading =
            isDemo ? DemoPullRequestDetailLoader() : GitHubPullRequestDetailLoader(client: gitHub)
        pullRequest = PullRequestScreenModel(loader: detailLoader)
        diff = DiffScreenModel(loader: isDemo ? DemoDiffLoader() : GitHubDiffLoader(client: gitHub))
        review = ReviewScreenModel(service: isDemo ? DemoReviewService() : GitHubReviewService(client: gitHub))
        review.isSubmitSheetPresented = arguments.contains("--submit-review")
        if let compose = Self.value(of: "--compose", in: arguments)?.split(separator: ":"), compose.count == 2,
            let line = Int(compose[1])
        {
            review.startComment(at: CodeLocation(path: String(compose[0]), line: line, side: .right), lineText: "")
        }
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
