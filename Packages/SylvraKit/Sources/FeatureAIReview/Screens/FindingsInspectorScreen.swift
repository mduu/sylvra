import DesignSystem
import SwiftUI
import SylvraCore

/// The AI inspector: run status, findings, patterns and summary (container).
public struct FindingsInspectorScreen: View {
    @Bindable var model: AIReviewModel
    private let pullRequest: PullRequestSummary?
    private let prBody: String
    private let jump: (ReviewFinding) -> Void
    private let turnIntoComment: ((ReviewFinding) -> Void)?
    let chat: AIChatModel?
    private let jumpToLocation: (String, Int) -> Void
    private let useAsComment: ((String, CodeLocation) -> Void)?
    /// Selects another pull request (the one whose review is running; wired by the app).
    private let showPullRequest: ((PullRequestID) -> Void)?
    /// The scroll view shows its end (chat: the "scroll to bottom" button hides).
    @State var isScrolledToBottom = true

    /// - Parameters:
    ///   - jump: shows the finding's location in the diff (wired by the app).
    ///   - turnIntoComment: creates a draft review comment (wired by the app, optional).
    public init(
        model: AIReviewModel, pullRequest: PullRequestSummary?, pullRequestBody: String,
        jump: @escaping (ReviewFinding) -> Void, turnIntoComment: ((ReviewFinding) -> Void)? = nil,
        chat: AIChatModel? = nil, jumpToLocation: @escaping (String, Int) -> Void = { _, _ in },
        useAsComment: ((String, CodeLocation) -> Void)? = nil,
        showPullRequest: ((PullRequestID) -> Void)? = nil
    ) {
        self.useAsComment = useAsComment
        self.showPullRequest = showPullRequest
        self.chat = chat
        self.jumpToLocation = jumpToLocation
        self.model = model
        self.pullRequest = pullRequest
        self.prBody = pullRequestBody
        self.jump = jump
        self.turnIntoComment = turnIntoComment
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            // Header and tabs stay put; only the tab content scrolls (long chats, many findings).
            header
            // The tabs are always there for a pull request: the chat works without a review, and the
            // findings and patterns tabs say how to get some.
            if let id = pullRequest?.id {
                SectionTabBar(items: tabItems(for: id), selection: $model.tab)
                scrollingContent(for: id)
            } else {
                ScrollView { emptyState }
            }
        }
        .padding([.horizontal, .top], 14)
        .animation(.snappy, value: model.progress)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .top)
        .background(SylvraColor.surfaceSidebar)
        .task { await model.detectAgent() }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack {
                Label("AI review", systemImage: "sparkles").aiFont(.callout, weight: .semibold)
                Spacer()
                Text(model.agentVersion.map { "\(model.providerName) \($0)" } ?? model.providerName)
                    .aiFont(.caption)
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
            }
            if let id = pullRequest?.id {
                let settings = model.settings(for: id)
                HStack(spacing: 6) {
                    ForEach(settings.models, id: \.self) { chip($0.capitalized) }
                    chip(settings.effort.capitalized)
                    chip(String(localized: "\(settings.maxParallelAgents) agents"))
                }
            }
            if let pullRequest {
                runControl(for: pullRequest)
            }
            if model.runningPullRequest == pullRequest?.id {
                if model.runState == .running, model.progress.isEmpty {
                    ReviewPreparationRowView(step: model.preparation ?? String(localized: "Starting…"))
                }
                if model.runState == .running, let started = model.runStartedAt {
                    ReviewRunningTimeView(started: started)
                }
                ForEach(model.progress, id: \.id) { AgentProgressRowView(progress: $0, time: model.stepTimes[$0.id]) }
                if model.runState == .done, let pullRequest, let result = model.results[pullRequest.id] {
                    ReviewTotalView(duration: result.duration, tokens: result.tokens)
                }
                if model.runState == .running {
                    Button("Cancel review", role: .cancel) { model.cancel() }.controlSize(.small)
                }
                if let warning = model.workspaceWarning {
                    Label(warning, systemImage: "exclamationmark.triangle").aiFont(.caption).foregroundStyle(.orange)
                }
                if case .failed(let message) = model.runState {
                    Text(message).aiFont(.caption).foregroundStyle(.red).lineLimit(4)
                }
            }
            if let pullRequest, let result = model.results[pullRequest.id], !isRunning(pullRequest.id) {
                ReviewFreshnessView(
                    isOutdated: model.isOutdated(pullRequest.id), reviewedAt: result.reviewedAt,
                    duration: result.duration, tokens: result.tokens,
                    isEnabled: model.runState != .running
                ) { run(pullRequest) }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    func content(for id: PullRequestID) -> some View {
        switch model.tab {
        case .findings:
            findingsContent(for: id)
        case .patterns:
            if model.results[id] == nil {
                noReviewYet(id, String(localized: "Patterns the AI review checks appear here after a review."))
            }
            if let patterns = model.results[id]?.patterns, !patterns.isEmpty {
                CopyAllRow(title: "Copy all patterns") {
                    AIReviewClipboard.patterns(patterns, pullRequest: pullRequestLine)
                }
            }
            ForEach(model.results[id]?.patterns ?? []) { pattern in
                PatternRowView(
                    pattern: pattern, isSelected: model.selectedPatternID == pattern.id, pullRequest: pullRequestLine
                ) { location in
                    model.selectedPatternID = pattern.id
                    model.selectedFindingID = nil
                    jumpToLocation(location.path, location.startLine)
                }
                .id(pattern.id)
            }
        case .chat:
            if let chat {
                AIChatPanel(model: chat, pullRequestID: id, jump: jumpToLocation, useAsComment: useAsComment)
            }
        }
    }

    @ViewBuilder private func findingsContent(for id: PullRequestID) -> some View {
        if model.results[id] == nil {
            noReviewYet(id, String(localized: "Findings appear here after an AI review."))
        }
        if let result = model.results[id], !result.overall.isEmpty || !model.visibleFindings(for: id).isEmpty {
            CopyAllRow(title: "Copy all findings") {
                AIReviewClipboard.findings(
                    model.visibleFindings(for: id), overall: result.overall, pullRequest: pullRequestLine)
            }
        }
        if let overall = model.results[id]?.overall, !overall.isEmpty {
            OverallFindingsView(points: overall, pullRequest: pullRequestLine)
        }
        ForEach(model.visibleFindings(for: id)) { finding in
            if model.selectedFindingID == finding.id {
                FindingDetailView(
                    finding: finding,
                    actions: FindingActions(
                        // Unanchored findings have no diff line a GitHub comment could attach to.
                        turnIntoComment: finding.isAnchored
                            ? turnIntoComment.map { action in { action(finding) } } : nil,
                        dismiss: { model.dismiss(finding) }),
                    pullRequest: pullRequestLine
                )
                .onTapGesture { model.selectedFindingID = nil }
                .id(finding.id)
            } else {
                FindingRowView(finding: finding, isSelected: false, pullRequest: pullRequestLine)
                    .contentShape(Rectangle())
                    .onTapGesture {
                        model.selectedFindingID = finding.id
                        jump(finding)
                    }
                    .id(finding.id)
            }
        }
        if let history = model.results[id]?.history, !history.isEmpty {
            VStack(alignment: .leading, spacing: 4) {
                Text("History").aiFont(.caption, weight: .semibold).foregroundStyle(.secondary)
                ForEach(history, id: \.self) { Text($0).aiFont(.caption) }
            }
            .padding(10)
            .frame(maxWidth: .infinity, alignment: .leading)
            .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, style: .init(dash: [4])) }
        }
    }

    /// The pull request in copied text.
    private var pullRequestLine: String? {
        AIReviewClipboard.pullRequestLine(pullRequest?.id, title: pullRequest?.title)
    }

    /// Same look as the pull request column's tabs: symbols, counts, narrowing to symbols.
    private func tabItems(for id: PullRequestID) -> [SectionTabItem<AIReviewModel.Tab>] {
        var items = [
            SectionTabItem(
                tab: AIReviewModel.Tab.findings, title: String(localized: "Findings"),
                symbol: "exclamationmark.bubble",
                // No badge before the first review (0 would read as "nothing found").
                count: model.results[id] == nil ? nil : model.visibleFindings(for: id).count),
            SectionTabItem(
                tab: AIReviewModel.Tab.patterns, title: String(localized: "Patterns"), symbol: "square.grid.3x3",
                count: model.results[id]?.patterns.count),
        ]
        if let chat {
            // Chats with at least one message (a new, empty chat doesn't count).
            let chats = chat.chatCount(for: id)
            items.append(
                SectionTabItem(
                    tab: AIReviewModel.Tab.chat, title: String(localized: "Chat"),
                    symbol: "bubble.left.and.text.bubble.right", count: chats > 0 ? chats : nil))
        }
        return items
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles").aiFont(.largeTitle).foregroundStyle(AIAccent.border)
            Text("Select a pull request").aiFont(.headline)
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
    }

    /// Findings and patterns before the first review (the run control is in the header).
    @ViewBuilder private func noReviewYet(_ id: PullRequestID, _ text: String) -> some View {
        if model.runningPullRequest != id || model.runState != .running {
            VStack(spacing: 8) {
                Image(systemName: "sparkles").aiFont(.title2).foregroundStyle(AIAccent.border)
                Text("No AI review yet").aiFont(.headline)
                Text(text).aiFont(.caption).foregroundStyle(.secondary).multilineTextAlignment(.center)
            }
            .frame(maxWidth: .infinity)
            .padding(.top, 24)
        }
    }

    /// Start, or what is in the way: one review runs at a time, possibly for another pull request.
    @ViewBuilder private func runControl(for pullRequest: PullRequestSummary) -> some View {
        let id = pullRequest.id
        if model.runState == .running, let other = model.runningPullRequest, other != id {
            OtherReviewRunningView(
                pullRequest: other, finished: model.finishedAgentCount, total: model.agentProgress.count,
                show: showPullRequest.map { show in { show(other) } },
                reviewHere: {
                    Task { await model.replaceRunningReview(with: id, title: pullRequest.title, body: prBody) }
                })
        } else if model.results[id] == nil, model.runState != .running || model.runningPullRequest != id {
            Button {
                run(pullRequest)
            } label: {
                Label("Run AI Review", systemImage: "sparkles").frame(maxWidth: .infinity)
            }
            .buttonStyle(.borderedProminent)
            .tint(SylvraColor.brandPrimary)
        }
    }

    private func isRunning(_ id: PullRequestID) -> Bool {
        model.runState == .running && model.runningPullRequest == id
    }

    private func run(_ pullRequest: PullRequestSummary) {
        Task { await model.run(pullRequest.id, title: pullRequest.title, body: prBody) }
    }

    private func chip(_ text: String) -> some View {
        Text(text)
            .aiFont(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(SylvraColor.brandPrimary.opacity(0.14), in: Capsule())
            .foregroundStyle(SylvraColor.brandPrimary)
    }
}
