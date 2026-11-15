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
    @Environment(\.openURL) private var openURL
    let environment: AppEnvironment
    @State private var selection: PullRequestSummary?
    @State private var isInspectorPresented: Bool
    @State private var columnVisibility: NavigationSplitViewVisibility

    init(environment: AppEnvironment) {
        self.environment = environment
        _isInspectorPresented = State(initialValue: environment.showsInspector)
        _columnVisibility = State(initialValue: environment.startsFocused ? .doubleColumn : .all)
    }

    var body: some View {
        NavigationSplitView(columnVisibility: $columnVisibility) {
            InboxScreen(model: environment.inbox, selection: $selection)
                .navigationSplitViewColumnWidth(min: 240, ideal: 290)
        } content: {
            PullRequestScreen(model: environment.pullRequest, pullRequest: selection) {
                DiffFileNavigatorPanel(model: environment.diff) { item in
                    NavigatorToolsMenu(environment: environment, item: item, pullRequest: selection?.id)
                }
            }
            .navigationSplitViewColumnWidth(min: 300, ideal: 360)
        } detail: {
            ReviewScreen(model: environment.review, pullRequestID: selection?.id) {
                DiffScreen(
                    model: environment.diff,
                    pullRequestID: selection?.id,
                    headSHA: environment.pullRequest.detail.flatMap {
                        $0.summary.id == selection?.id ? $0.headSHA : nil
                    },
                    lineAccessory: { ReviewThreadsPanel(model: environment.review, location: $0) },
                    onStartComment: { environment.review.startComment(at: $0, lineText: $1) }
                )
            }
            .terminalPanel(environment, selection: selection)
        }
        .navigationTitle(Text(verbatim: selection.map { "\($0.id.repository) #\($0.id.number)" } ?? "Sylvra"))
        .navigationSubtitle(Text(verbatim: selection?.title ?? ""))
        .inspector(isPresented: $isInspectorPresented) {
            FindingsInspectorScreen(
                model: environment.aiReview,
                pullRequest: selection,
                pullRequestBody: environment.pullRequest.detail?.body ?? "",
                jump: { finding in environment.diff.selectedPath = finding.path },
                turnIntoComment: { finding in startComment(from: finding) },
                chat: environment.chat,
                jumpToLocation: { path, _ in environment.diff.selectedPath = path }
            )
            .inspectorColumnWidth(min: 260, ideal: 300)
        }
        .task(id: selection?.id) {
            guard environment.autoRunsAIReview, let selection else { return }
            await environment.aiReview.run(selection.id, title: selection.title, body: "")
        }
        .focusedSceneValue(\.reviewActions, reviewActions)
        .onChange(of: environment.diff.selectedPath) { _, path in
            environment.chat.context.file = path
        }
        .onChange(of: environment.aiReview.selectedFindingID) { _, id in
            environment.chat.context.finding =
                environment.aiReview.findings(for: selection?.id)
                .first { $0.id == id }?.title
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
            guard selection == nil, let wanted = environment.initialSelection else { return }
            selection = environment.inbox.snapshot.sections.values.joined().first { $0.id.description == wanted }
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
                isSelected: finding.id == environment.aiReview.selectedFindingID)
        }
    }

    /// Prefills the review composer with an AI finding; the reviewer edits and owns the comment.
    private func startComment(from finding: ReviewFinding) {
        let location = CodeLocation(
            path: finding.path, line: finding.endLine, side: .right, startLine: finding.startLine)
        var body = "**\(finding.title)**\n\n\(finding.rationale)"
        if let suggestion = finding.suggestion { body += "\n\n" + SuggestionBlock.make(code: suggestion) }
        environment.review.draft = CommentDraft(
            location: location, lineText: environment.diff.text(at: location), body: body)
        environment.diff.selectedPath = finding.path
    }

    /// Menu bar / keyboard actions for this window.
    private var reviewActions: ReviewActions {
        ReviewActions(
            nextFile: { environment.diff.selectFile(offset: 1) },
            previousFile: { environment.diff.selectFile(offset: -1) },
            nextFinding: { jump(to: environment.aiReview.selectFinding(offset: 1, for: selection?.id)) },
            previousFinding: { jump(to: environment.aiReview.selectFinding(offset: -1, for: selection?.id)) },
            toggleViewed: {
                guard let path = environment.diff.selectedPath ?? environment.diff.orderedFiles.first?.path else {
                    return
                }
                Task { await environment.diff.toggleViewed(path) }
            },
            runAIReview: {
                guard let selection else { return }
                Task {
                    await environment.aiReview.run(
                        selection.id, title: selection.title, body: environment.pullRequest.detail?.body ?? "")
                }
            },
            openOnGitHub: { if let url = selection?.url { openURL(url) } },
            toggleInspector: { isInspectorPresented.toggle() }
        )
    }

    private func jump(to finding: ReviewFinding?) {
        guard let finding else { return }
        isInspectorPresented = true
        environment.diff.selectedPath = finding.path
    }
}

#Preview {
    RootScreen(environment: AppEnvironment(arguments: ["--demo"]))
}
