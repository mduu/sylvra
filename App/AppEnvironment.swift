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
/// - `--scope=fullFile`: start the diff with full files
/// - `--focus`: hide the inbox sidebar; `--no-inspector`: hide the AI inspector
/// - `--new-commits` (demo): simulate a push a few seconds after start
/// - `--run-ai-review`: start an AI review as soon as a PR is selected; with `--turn-into-comment` the top
///   finding becomes a comment draft
/// - `--submit-review`: open the submit review sheet; `--compose=path:line`: open the comment composer
///   (`--draft=text` prefills it)
/// - `--terminal`: show the terminal panel with one tab; `--commands`: show the Commands list
/// - `--ask=question`: ask the AI chat this question once a PR is selected (screenshots)
/// - `--window-layout=wide|compact|focus|…`: window layout for this launch (see `WindowLayout`)
@MainActor
final class AppEnvironment {
    let isDemo: Bool
    let initialSelection: String?
    let startsFocused: Bool
    let showsInspector: Bool
    let autoRunsAIReview: Bool
    let autoTurnsIntoComment: Bool
    /// Screenshots: a question for the AI chat once a PR is selected (`--ask=…`).
    let initialQuestion: String?
    /// Screenshots: review this commit (1-based) on its own (`--commit=2`).
    let initialCommit: Int?
    /// Screenshots: open the report of the first failing check (`--open-check`).
    let opensFailingCheck: Bool
    let gitHub: GitHubClient
    let inbox: InboxScreenModel
    let pullRequest: PullRequestScreenModel
    let diff: DiffScreenModel
    let openInIDE: OpenInIDEModel
    /// Sylvra's worktrees: listed in the settings, cleaned up in the background.
    let worktrees: WorktreesModel
    let aiReview: AIReviewModel
    let chat: AIChatModel
    let activity = ActivityCenter()
    let notifications = NotificationRouter()
    let review: ReviewScreenModel
    let conversation: ConversationModel
    let terminal = TerminalModel()
    let bottomPanel = BottomPanelState()
    /// Selection and inspector state shared by the main and the review window.
    let window: WindowState
    let customTools = CustomToolStore()

    // swiftlint:disable:next function_body_length
    init(arguments: [String] = CommandLine.arguments) {
        isDemo = arguments.contains("--demo")
        initialSelection = Self.value(of: "--select", in: arguments)
        startsFocused = arguments.contains("--focus")
        showsInspector = !arguments.contains("--no-inspector")
        window = WindowState(isInspectorPresented: !arguments.contains("--no-inspector"))
        autoRunsAIReview = arguments.contains("--run-ai-review")
        autoTurnsIntoComment = arguments.contains("--turn-into-comment")
        initialQuestion = Self.value(of: "--ask", in: arguments)
        initialCommit = Self.value(of: "--commit", in: arguments).flatMap(Int.init)
        opensFailingCheck = arguments.contains("--open-check")
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
        aiReview.currentHeadSHA = { id in details.detail.flatMap { $0.summary.id == id ? $0.headSHA : nil } }
        chat = AIChatModel(
            provider: agent,
            settings: { id in reviews.settings(for: id) },
            prContext: { id in ChatContext.describe(id, detail: details.detail, review: reviews.results[id]) },
            workspace: { id in try await checkout?.prepareWorktree(for: id, purpose: .agent) }
        )
        review = ReviewScreenModel(service: isDemo ? DemoReviewService() : GitHubReviewService(client: gitHub))
        conversation = ConversationModel(
            service: isDemo ? DemoConversationService() : GitHubConversationService(client: gitHub))
        Self.configureCommentRewriting(review, agent: agent, isDemo: isDemo)
        conversation.rewriter = review.rewriter
        conversation.defaultCommentLanguage = review.defaultCommentLanguage
        review.isSubmitSheetPresented = arguments.contains("--submit-review")
        if let compose = Self.value(of: "--compose", in: arguments)?.split(separator: ":"), compose.count == 2,
            let line = Int(compose[1])
        {
            review.startComment(at: CodeLocation(path: String(compose[0]), line: line, side: .right), lineText: "")
            review.draft?.body = Self.value(of: "--draft", in: arguments) ?? ""
        }
        if arguments.contains("--terminal") { terminal.show() }
        if arguments.contains("--commands") { bottomPanel.showsCommands = true }
        if Self.value(of: "--layout", in: arguments) == "inline" { diff.layout = .inline }
        if let scope = Self.value(of: "--scope", in: arguments).flatMap(DiffScreenModel.Scope.init(rawValue:)) {
            diff.scope = scope
        }
        if let tab = Self.value(of: "--tab", in: arguments).flatMap(PullRequestScreenModel.Tab.init(rawValue:)) {
            pullRequest.tab = tab
        }
        worktrees = Self.makeWorktrees(
            gitHub: gitHub, isDemo: isDemo, window: window, aiReview: aiReview, terminal: terminal)
        if !isDemo {
            let worktrees = worktrees
            Task { await worktrees.keepCleaning() }
        }
    }

    /// Worktrees in use (shown, reviewed, open in a terminal tab) are never removed automatically.
    /// Demo launches use an empty folder, so screenshots never list or touch real worktrees.
    private static func makeWorktrees(
        gitHub: GitHubClient, isDemo: Bool, window: WindowState, aiReview: AIReviewModel, terminal: TerminalModel
    ) -> WorktreesModel {
        let cleaner =
            isDemo
            ? WorktreeCleaner(storageRoot: FileManager.default.temporaryDirectory.appending(path: "SylvraDemo"))
            : WorktreeCleaner()
        return WorktreesModel(
            cleaner: cleaner,
            isOpen: { id in isDemo ? nil : try? await gitHub.isPullRequestOpen(id) },
            usage: {
                var pullRequests = Set([window.selectedID].compactMap { $0 })
                if aiReview.runState == .running, let running = aiReview.runningPullRequest {
                    pullRequests.insert(running)
                }
                return WorktreesModel.Usage(
                    pullRequests: pullRequests, directories: terminal.sessions.map(\.directory))
            })
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
