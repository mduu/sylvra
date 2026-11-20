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
    /// The scroll view shows its end (chat: the "scroll to bottom" button hides).
    @State var isScrolledToBottom = true

    /// - Parameters:
    ///   - jump: shows the finding's location in the diff (wired by the app).
    ///   - turnIntoComment: creates a draft review comment (wired by the app, optional).
    public init(
        model: AIReviewModel, pullRequest: PullRequestSummary?, pullRequestBody: String,
        jump: @escaping (ReviewFinding) -> Void, turnIntoComment: ((ReviewFinding) -> Void)? = nil,
        chat: AIChatModel? = nil, jumpToLocation: @escaping (String, Int) -> Void = { _, _ in },
        useAsComment: ((String, CodeLocation) -> Void)? = nil
    ) {
        self.useAsComment = useAsComment
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
            if let id = pullRequest?.id, hasContent(id) {
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

    private func hasContent(_ id: PullRequestID) -> Bool {
        model.results[id] != nil || !model.progress.isEmpty || !(chat?.messages(for: id).isEmpty ?? true)
            || model.tab == .chat
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
            if model.runningPullRequest == pullRequest?.id {
                ForEach(model.progress, id: \.id) { AgentProgressRowView(progress: $0) }
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
            if let overall = model.results[id]?.overall, !overall.isEmpty {
                OverallFindingsView(points: overall)
            }
            ForEach(model.visibleFindings(for: id)) { finding in
                if model.selectedFindingID == finding.id {
                    FindingDetailView(
                        finding: finding,
                        actions: FindingActions(
                            // Unanchored findings have no diff line a GitHub comment could attach to.
                            turnIntoComment: finding.isAnchored
                                ? turnIntoComment.map { action in { action(finding) } } : nil,
                            dismiss: { model.dismiss(finding) })
                    )
                    .onTapGesture { model.selectedFindingID = nil }
                    .id(finding.id)
                } else {
                    FindingRowView(finding: finding, isSelected: false)
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
        case .patterns:
            ForEach(model.results[id]?.patterns ?? []) { pattern in
                PatternRowView(pattern: pattern, isSelected: model.selectedPatternID == pattern.id) { location in
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

    /// Same look as the pull request column's tabs: symbols, counts, narrowing to symbols.
    private func tabItems(for id: PullRequestID) -> [SectionTabItem<AIReviewModel.Tab>] {
        var items = [
            SectionTabItem(
                tab: AIReviewModel.Tab.findings, title: String(localized: "Findings"),
                symbol: "exclamationmark.bubble", count: model.visibleFindings(for: id).count),
            SectionTabItem(
                tab: AIReviewModel.Tab.patterns, title: String(localized: "Patterns"), symbol: "square.grid.3x3",
                count: model.results[id]?.patterns.count),
        ]
        if let chat {
            let messages = chat.messages(for: id).count { $0.role == .assistant }
            items.append(
                SectionTabItem(
                    tab: AIReviewModel.Tab.chat, title: String(localized: "Chat"),
                    symbol: "bubble.left.and.text.bubble.right", count: messages > 0 ? messages : nil))
        }
        return items
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles").aiFont(.largeTitle).foregroundStyle(AIAccent.border)
            Text(pullRequest == nil ? "Select a pull request" : "No AI review yet")
                .aiFont(.headline)
            if let pullRequest {
                Button {
                    run(pullRequest)
                } label: {
                    Label("Run AI Review", systemImage: "sparkles")
                }
                .buttonStyle(.borderedProminent)
                .disabled(model.runState == .running)
                if chat != nil {
                    Button("Ask a question") { model.tab = .chat }.buttonStyle(.borderless)
                }
            }
        }
        .frame(maxWidth: .infinity)
        .padding(.top, 40)
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
