import FeatureAIReview
import FeatureActivity
import FeatureCustomTools
import FeatureDiff
import FeatureInbox
import FeatureOpenInIDE
import FeaturePullRequest
import FeatureReview
import FeatureTerminal
import Foundation
import Platform
import SylvraCore

/// Composition root: creates the services and feature models of the app.
///
/// Launch arguments (used for demos and screenshots):
/// - `--demo`: fixture data instead of GitHub
/// - `--select=owner/repo#number`: select that PR once the inbox is loaded
/// - `--tab=overview|commits|checks`: initial tab of the PR column
/// - `--layout=inline`: inline instead of side-by-side diff
/// - `--focus`: hide the inbox sidebar; `--no-inspector`: hide the AI inspector
/// - `--new-commits` (demo): simulate a push a few seconds after start
/// - `--run-ai-review`: start an AI review as soon as a PR is selected; with `--turn-into-comment` the top
///   finding becomes a comment draft
/// - `--submit-review`: open the submit review sheet; `--compose=path:line`: open the comment composer
///   (`--draft=text` prefills it)
/// - `--terminal`: show the terminal panel with one tab
@MainActor
final class AppEnvironment {
    let isDemo: Bool
    let initialSelection: String?
    let startsFocused: Bool
    let showsInspector: Bool
    let autoRunsAIReview: Bool
    let autoTurnsIntoComment: Bool
    let gitHub: GitHubClient
    let inbox: InboxScreenModel
    let pullRequest: PullRequestScreenModel
    let diff: DiffScreenModel
    let openInIDE: OpenInIDEModel
    let aiReview: AIReviewModel
    let chat: AIChatModel
    let activity = ActivityCenter()
    let review: ReviewScreenModel
    let terminal = TerminalModel()
    let customTools = CustomToolStore()

    init(arguments: [String] = CommandLine.arguments) {
        isDemo = arguments.contains("--demo")
        initialSelection = Self.value(of: "--select", in: arguments)
        startsFocused = arguments.contains("--focus")
        showsInspector = !arguments.contains("--no-inspector")
        autoRunsAIReview = arguments.contains("--run-ai-review")
        autoTurnsIntoComment = arguments.contains("--turn-into-comment")
        gitHub = GitHubClient(tokenProvider: GitHubCLITokenProvider())
        let inboxLoader: any InboxLoading = isDemo ? DemoInboxLoader() : GitHubInboxLoader(client: gitHub)
        inbox = Self.makeInbox(loader: inboxLoader, gitHub: gitHub, isDemo: isDemo, arguments: arguments)
        let detailLoader: any PullRequestDetailLoading =
            isDemo ? DemoPullRequestDetailLoader() : GitHubPullRequestDetailLoader(client: gitHub)
        pullRequest = PullRequestScreenModel(loader: detailLoader)
        openInIDE =
            isDemo
            ? OpenInIDEModel(checkout: DemoCheckout(), opener: DemoIDEOpener())
            : OpenInIDEModel(checkout: CheckoutService(), opener: IDELauncher())
        let diffLoader: any DiffLoading =
            isDemo
            ? DemoDiffLoader(simulatesPush: arguments.contains("--new-commits")) : GitHubDiffLoader(client: gitHub)
        diff = DiffScreenModel(loader: diffLoader, pollInterval: isDemo ? .seconds(2) : .seconds(60))
        // AI agents read a per-PR worktree (never the shared IDE worktree, which may switch PRs meanwhile).
        let checkout: CheckoutService? = isDemo ? nil : CheckoutService()
        let agent: any AgentProvider = isDemo ? DemoAgentProvider() : ClaudeCodeProvider()
        aiReview = AIReviewModel(
            engine: ReviewEngine(provider: agent),
            files: { id in ReviewableFiles.make(from: try await diffLoader.loadDiff(for: id).files) },
            workspace: { id in try await checkout?.prepareWorktree(for: id, purpose: .agent) },
            cache: isDemo ? nil : JSONCache()
        )
        let reviews = aiReview
        let details = pullRequest
        chat = AIChatModel(
            provider: agent,
            settings: { id in reviews.settings(for: id) },
            prContext: { id in ChatContext.describe(id, detail: details.detail, review: reviews.results[id]) },
            workspace: { id in try await checkout?.prepareWorktree(for: id, purpose: .agent) }
        )
        review = ReviewScreenModel(service: isDemo ? DemoReviewService() : GitHubReviewService(client: gitHub))
        Self.configureCommentRewriting(review, agent: agent, isDemo: isDemo)
        review.isSubmitSheetPresented = arguments.contains("--submit-review")
        if let compose = Self.value(of: "--compose", in: arguments)?.split(separator: ":"), compose.count == 2,
            let line = Int(compose[1])
        {
            review.startComment(at: CodeLocation(path: String(compose[0]), line: line, side: .right), lineText: "")
            review.draft?.body = Self.value(of: "--draft", in: arguments) ?? ""
        }
        if arguments.contains("--terminal") { terminal.show() }
        if Self.value(of: "--layout", in: arguments) == "inline" { diff.layout = .inline }
        if let tab = Self.value(of: "--tab", in: arguments).flatMap(PullRequestScreenModel.Tab.init(rawValue:)) {
            pullRequest.tab = tab
        }
    }

    private static func makeInbox(
        loader: any InboxLoading, gitHub: GitHubClient, isDemo: Bool, arguments: [String]
    ) -> InboxScreenModel {
        let inbox = InboxScreenModel(
            loader: loader, cache: isDemo ? nil : JSONCache(),
            repositorySearcher: isDemo ? DemoRepositorySearcher() : GitHubRepositorySearcher(client: gitHub),
            repositoryLoader: isDemo
                ? DemoRepositoryPullRequestLoader() : GitHubRepositoryPullRequestLoader(client: gitHub),
            defaults: isDemo ? nil : .standard)
        inbox.isChoosingRepositories = arguments.contains("--choose-repositories")
        if isDemo {
            // Demo: a few repositories in the sidebar; `--repository=billing` opens one.
            Task { @MainActor in
                for name in ["billing", "payments", "identity", "catalog", "ios-app"] {
                    await inbox.addRepository(InboxRepository(owner: "acme", name: name))
                }
                if let name = value(of: "--repository", in: arguments) {
                    inbox.openRepository(InboxRepository(owner: "acme", name: name))
                }
            }
        }
        return inbox
    }

    /// `--flag=value` (preferred: a separate bare value would be opened as a document by AppKit, and the
    /// main window would not appear) or `--flag value`.
    private static func value(of flag: String, in arguments: [String]) -> String? {
        if let inline = arguments.first(where: { $0.hasPrefix(flag + "=") }) {
            return String(inline.dropFirst(flag.count + 1))
        }
        guard let index = arguments.firstIndex(of: flag), arguments.indices.contains(index + 1) else { return nil }
        return arguments[index + 1]
    }

    /// Comment language default and the AI rewriter (demo: canned rewrite without an agent call).
    private static func configureCommentRewriting(_ review: ReviewScreenModel, agent: any AgentProvider, isDemo: Bool) {
        review.defaultCommentLanguage = UserDefaults.standard.string(forKey: "commentLanguage") ?? "English"
        let rewriter = CommentRewriter(provider: agent)
        review.rewriter =
            isDemo
            ? { @Sendable text, language, style in
                try await DemoCommentRewriter.rewrite(text, language: language, style: style)
            }
            : { @Sendable text, language, style in try await rewriter.rewrite(text, language: language, style: style) }
    }
}
