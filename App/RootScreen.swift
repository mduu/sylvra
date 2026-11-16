import DesignSystem
import FeatureAIReview
import FeatureActivity
import FeatureDiff
import FeatureInbox
import FeatureOpenInIDE
import FeaturePullRequest
import FeatureReview
import SwiftUI
import SylvraCore

/// Main window layout: inbox · pull request · diff, with the AI inspector on the right.
/// Composes feature slices — slices themselves never import each other.
struct RootScreen: View {
    @Environment(\.openURL) var openURL
    let environment: AppEnvironment
    @State private var selectedID: PullRequestID?

    /// The selected PR's latest summary from the inbox.
    var selection: PullRequestSummary? { selectedID.flatMap(environment.inbox.summary(for:)) }
    @State var isInspectorPresented: Bool
    @State private var columnVisibility: NavigationSplitViewVisibility
    @State var overlay: Overlay?
    @State private var keyboard = KeyboardNavigator()
    /// Column widths of the last session (read once at launch, see `ColumnLayout`).
    private let inboxWidth = ColumnLayout.initialWidth(.inbox)
    private let pullRequestWidth = ColumnLayout.initialWidth(.pullRequest)
    private let inspectorWidth = ColumnLayout.initialWidth(.inspector)

    init(environment: AppEnvironment) {
        self.environment = environment
        _isInspectorPresented = State(initialValue: environment.showsInspector)
        _columnVisibility = State(initialValue: environment.startsFocused ? .doubleColumn : .all)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            InboxScreen(model: environment.inbox, selection: $selectedID)
                .rememberedColumn(.inbox, ideal: inboxWidth)
                .navigationSplitViewColumnWidth(
                    min: ColumnLayout.Column.inbox.range.lowerBound, ideal: inboxWidth,
                    max: ColumnLayout.Column.inbox.range.upperBound)
        } content: {
            PullRequestScreen(
                model: environment.pullRequest, pullRequest: selection,
                selectedCommitSHA: environment.diff.selectedCommit?.sha,
                selectCommit: { commit in Task { await environment.diff.showCommit(commit) } },
                summary: {
                    AISummaryPanel(model: environment.aiReview, pullRequestID: selection?.id) { path in
                        environment.diff.selectedPath = path
                    }
                },
                overviewTop: { ChangeMapPanel(model: environment.diff) },
                files: {
                    DiffFileNavigatorPanel(model: environment.diff) { item in
                        NavigatorToolsMenu(environment: environment, item: item, pullRequest: selection?.id)
                    }
                }
            )
            .rememberedColumn(.pullRequest, ideal: pullRequestWidth)
            .navigationSplitViewColumnWidth(
                min: ColumnLayout.Column.pullRequest.range.lowerBound, ideal: pullRequestWidth,
                max: ColumnLayout.Column.pullRequest.range.upperBound)
        } detail: {
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
        .containerBackground(SylvraColor.surfacePrimary, for: .window)
        .toolbarBackground(SylvraColor.surfacePrimary, for: .windowToolbar)
        .toolbarBackgroundVisibility(.visible, for: .windowToolbar)
        .navigationTitle(Text(verbatim: selection.map { "\($0.id.repository) #\($0.id.number)" } ?? "Sylvra"))
        .navigationSubtitle(Text(verbatim: selection?.title ?? ""))
        .inspector(isPresented: $isInspectorPresented) {
            FindingsInspectorScreen(
                model: environment.aiReview,
                pullRequest: selection,
                pullRequestBody: environment.pullRequest.detail?.body ?? "",
                jump: { finding in environment.diff.focus(path: finding.path, line: finding.startLine) },
                turnIntoComment: { finding in startComment(from: finding) },
                chat: environment.chat,
                jumpToLocation: { path, line in environment.diff.focus(path: path, line: line) },
                useAsComment: { answer, location in useAsComment(answer, at: location) }
            )
            .rememberedColumn(.inspector, ideal: inspectorWidth)
            .inspectorColumnWidth(
                min: ColumnLayout.Column.inspector.range.lowerBound, ideal: inspectorWidth,
                max: ColumnLayout.Column.inspector.range.upperBound)
        }
        .task(id: selection?.id) {
            guard environment.autoRunsAIReview, let selection else { return }
            await environment.aiReview.run(selection.id, title: selection.title, body: "")
            // Screenshots / demos: show the top finding in the diff right away.
            if let first = environment.aiReview.findings(for: selection.id).first {
                environment.aiReview.selectedFindingID = first.id
                if environment.autoTurnsIntoComment { startComment(from: first) }
            }
        }
        .focusedSceneValue(\.reviewActions, reviewActions)
        .onChange(of: environment.pullRequest.detail?.commits, initial: true) { _, commits in
            // Commit-by-commit review needs the PR's commits (oldest first, as GitHub lists them).
            applyCommits(commits)
        }
        .onChange(of: environment.diff.selectedPath) { _, path in
            environment.chat.context.file = path
        }
        .onChange(of: environment.aiReview.selectedFindingID) { _, id in
            environment.chat.context.finding =
                environment.aiReview.findings(for: selection?.id)
                .first { $0.id == id }?.title
        }
        .onAppear {
            // A click on an AI highlight in the diff opens that finding (card in the diff, row in the inspector).
            environment.diff.selectFinding = { id in
                withAnimation(.snappy) { environment.aiReview.selectedFindingID = UUID(uuidString: id) }
            }
            environment.review.discussHandler = { location, code, question in
                discuss(location, code: code, question: question)
            }
            keyboard.handler = { key in handleKey(key) }
            keyboard.start()
        }
        .onDisappear { keyboard.stop() }
        .sheet(item: $overlay) { overlay in
            switch overlay {
            case .palette: CommandPaletteSheet(items: paletteItems)
            case .shortcuts: KeyboardShortcutsSheet()
            }
        }
        .onChange(of: aiReadingOrder, initial: true) { _, order in
            withAnimation(.snappy) { environment.diff.readingOrder = order }
        }
        .onChange(of: aiHighlights) { _, highlights in
            withAnimation(.snappy) { environment.diff.lineHighlights = highlights }
        }
        .onChange(of: environment.aiReview.runState) { _, state in
            let id = "ai-review"
            switch state {
            case .running:
                environment.activity.start(ActivityJob(id: id, kind: .aiReview, title: String(localized: "AI review")))
            case .done:
                let count = environment.aiReview.visibleFindings(for: environment.aiReview.runningPullRequest).count
                environment.activity.finish(id, message: String(localized: "Review finished — \(count) findings"))
            case .failed(let message):
                environment.activity.finish(id, message: message)
            case .idle:
                environment.activity.finish(id, message: nil)
            }
        }
        .onChange(of: environment.openInIDE.status) { _, status in
            if case .working(let message) = status {
                environment.activity.start(ActivityJob(id: "checkout", kind: .checkout, title: message))
            } else {
                environment.activity.finish("checkout", message: nil)
            }
        }
        .onChange(of: environment.inbox.snapshot) {
            guard selectedID == nil, let wanted = environment.initialSelection else { return }
            selectedID = environment.inbox.snapshot.sections.values.joined().first { $0.id.description == wanted }?.id
        }
        .overlay(alignment: .bottom) {
            OpenInIDEStatusToast(status: environment.openInIDE.status)
                .padding(.bottom, 16)
                .animation(.snappy, value: environment.openInIDE.status)
        }
        .toolbar {
            ToolbarItem(placement: .primaryAction) {
                ActivityToolbarPanel(center: environment.activity)
            }
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
                Button {
                    isInspectorPresented.toggle()
                } label: {
                    Label("AI Inspector", systemImage: "sidebar.right")
                }
            }
        }
    }

    /// Prefills the review composer with an AI finding; the reviewer edits and owns the comment.
    private func startComment(from finding: ReviewFinding) {
        let location = CodeLocation(
            path: finding.path, line: finding.endLine, side: .right, startLine: finding.startLine)
        var body = finding.rationale
        if let suggestion = finding.suggestion { body += "\n\n" + SuggestionBlock.make(code: suggestion) }
        environment.review.draft = CommentDraft(
            location: location, lineText: environment.diff.text(at: location), body: body)
        environment.diff.focus(path: finding.path, line: finding.endLine)
        // Start from a personal draft in the language last used for this repository; the reviewer edits it.
        Task { await environment.review.rewriteDraft() }
    }

    /// Menu bar / keyboard actions for this window.

    func jump(to finding: ReviewFinding?) {
        guard let finding else { return }
        isInspectorPresented = true
        environment.diff.focus(path: finding.path, line: finding.startLine)
    }

    /// Below a diff line: review threads, and the selected AI finding as an inline card at its last line.
    @ViewBuilder
    private func lineAccessory(at location: CodeLocation) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            ReviewThreadsPanel(model: environment.review, location: location)
            if environment.chat.discussedLocations(for: selection?.id).contains(where: {
                $0.path == location.path && $0.side == location.side && $0.line == location.line
            }) {
                DiscussionMarkerView(open: openChat)
                    .padding(.horizontal, 12)
                    .padding(.vertical, 6)
            }
            if let finding = selectedFinding, location.side == .right, location.path == finding.path,
                location.line == finding.endLine
            {
                InlineFindingCard(
                    finding: finding,
                    originalLines: environment.diff.text(
                        at: CodeLocation(
                            path: finding.path, line: finding.endLine, side: .right, startLine: finding.startLine)),
                    ideName: selection.map { environment.openInIDE.preferredIDE(for: $0.id).name },
                    actions: FindingActions(
                        turnIntoComment: { startComment(from: finding) },
                        askInChat: {
                            environment.chat.context.finding = finding.title
                            environment.aiReview.tab = .chat
                            isInspectorPresented = true
                        },
                        openInIDE: {
                            guard let id = selection?.id else { return }
                            Task { await environment.openInIDE.open(id, file: finding.path, line: finding.startLine) }
                        },
                        dismiss: { withAnimation(.snappy) { environment.aiReview.dismiss(finding) } }
                    )
                )
                .padding(.vertical, 10)
                .padding(.horizontal, 12)
                .transition(.opacity.combined(with: .scale(scale: 0.97, anchor: .top)))
            }
        }
        .animation(.snappy, value: environment.aiReview.selectedFindingID)
    }

    private var aiReadingOrder: [ReadingStep] {
        selection.flatMap { environment.aiReview.results[$0.id]?.readingOrder } ?? []
    }

    private var selectedFinding: ReviewFinding? {
        environment.aiReview.findings(for: selection?.id).first { $0.id == environment.aiReview.selectedFindingID }
    }
}

// MARK: - AI discussion

extension RootScreen {
    /// Hands the PR's commits to the diff (commit-by-commit review); demo launches open a commit or a check.
    func applyCommits(_ commits: [Commit]?) {
        environment.diff.commits = commits ?? []
        if let number = environment.initialCommit, let commits, commits.indices.contains(number - 1) {
            environment.pullRequest.tab = .commits
            Task {
                // The diff of the PR loads in parallel; the commit needs it first.
                for _ in 0..<30 where environment.diff.loadState != .loaded {
                    try? await Task.sleep(for: .milliseconds(100))
                }
                await environment.diff.showCommit(commits[number - 1])
            }
        }
        if environment.opensFailingCheck,
            let failing = environment.pullRequest.detail?.checks.first(where: { $0.state == .failure })
        {
            environment.pullRequest.tab = .checks
            environment.pullRequest.openedCheck = failing
        }
    }

    private func openChat() {
        environment.aiReview.tab = .chat
        isInspectorPresented = true
    }

    /// Composer → private AI discussion about the selected lines.
    private func discuss(_ location: CodeLocation, code: String, question: String) {
        guard let id = selection?.id else { return }
        openChat()
        Task {
            await environment.chat.discuss(
                AIChatModel.CodeSnippet(location: location, text: code), question: question, for: id)
        }
    }

    /// Chat answer → short, factual draft comment on the discussed code (edited before posting).
    private func useAsComment(_ answer: String, at location: CodeLocation) {
        environment.review.draft = CommentDraft(
            location: location, lineText: environment.diff.text(at: location), body: answer)
        if location.side == .right { environment.diff.focus(path: location.path, line: location.line) }
        Task { await environment.review.rewriteDraft(.shorten) }
    }
}

extension RootScreen {
    /// AI findings of the selected PR as diff highlights (bridges FeatureAIReview → FeatureDiff).
    private var aiHighlights: [LineHighlight] {
        environment.aiReview.findings(for: selection?.id).map { finding in
            let intensity: Double =
                switch finding.severity {
                case .critical: 1
                case .major: 0.8
                case .minor: 0.5
                case .nit: 0.25
                }
            return LineHighlight(
                path: finding.path, lines: finding.startLine...finding.endLine, intensity: intensity,
                isSelected: finding.id == environment.aiReview.selectedFindingID, findingID: finding.id.uuidString)
        }
    }
}

#Preview {
    RootScreen(environment: AppEnvironment(arguments: ["--demo"]))
}
