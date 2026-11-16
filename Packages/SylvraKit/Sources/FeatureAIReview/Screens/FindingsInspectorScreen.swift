import DesignSystem
import SwiftUI
import SylvraCore

/// The AI inspector: run status, findings, patterns and summary (container).
public struct FindingsInspectorScreen: View {
    @Bindable private var model: AIReviewModel
    private let pullRequest: PullRequestSummary?
    private let prBody: String
    private let jump: (ReviewFinding) -> Void
    private let turnIntoComment: ((ReviewFinding) -> Void)?
    private let chat: AIChatModel?
    private let jumpToLocation: (String, Int) -> Void
    private let useAsComment: ((String, CodeLocation) -> Void)?

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
                Picker("Section", selection: $model.tab) {
                    Text("Findings \(model.visibleFindings(for: id).count)").tag(AIReviewModel.Tab.findings)
                    Text("Patterns").tag(AIReviewModel.Tab.patterns)
                    if chat != nil { Text("Chat").tag(AIReviewModel.Tab.chat) }
                }
                .pickerStyle(.segmented)
                .labelsHidden()
                ScrollViewReader { proxy in
                    ScrollView {
                        VStack(alignment: .leading, spacing: 12) {
                            content(for: id)
                        }
                        .padding(.bottom, 14)
                        .animation(.snappy, value: model.selectedFindingID)
                    }
                    .onChange(of: model.selectedFindingID) { _, selected in
                        guard let selected else { return }
                        // A highlight clicked in the diff: show the finding here as well.
                        model.tab = .findings
                        withAnimation(.snappy) { proxy.scrollTo(selected, anchor: .top) }
                    }
                }
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
                Label("AI review", systemImage: "sparkles").font(.callout.weight(.semibold))
                Spacer()
                Text(model.agentVersion.map { "\(model.providerName) \($0)" } ?? model.providerName)
                    .font(.caption)
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
                    Label(warning, systemImage: "exclamationmark.triangle").font(.caption).foregroundStyle(.orange)
                }
                if case .failed(let message) = model.runState {
                    Text(message).font(.caption).foregroundStyle(.red).lineLimit(4)
                }
            }
        }
        .padding(12)
        .background(.quaternary.opacity(0.4), in: RoundedRectangle(cornerRadius: 12))
    }

    @ViewBuilder
    private func content(for id: PullRequestID) -> some View {
        switch model.tab {
        case .findings:
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
                    Text("History").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
                    ForEach(history, id: \.self) { Text($0).font(.caption) }
                }
                .padding(10)
                .frame(maxWidth: .infinity, alignment: .leading)
                .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(.quaternary, style: .init(dash: [4])) }
            }
        case .patterns:
            ForEach(model.results[id]?.patterns ?? []) { pattern in
                PatternRowView(pattern: pattern) { location in jumpToLocation(location.path, location.startLine) }
            }
        case .chat:
            if let chat {
                AIChatPanel(model: chat, pullRequestID: id, jump: jumpToLocation, useAsComment: useAsComment)
            }
        }
    }

    private var emptyState: some View {
        VStack(spacing: 10) {
            Image(systemName: "sparkles").font(.largeTitle).foregroundStyle(AIAccent.border)
            Text(pullRequest == nil ? "Select a pull request" : "No AI review yet")
                .font(.headline)
            if let pullRequest {
                Button {
                    Task { await model.run(pullRequest.id, title: pullRequest.title, body: prBody) }
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

    private func chip(_ text: String) -> some View {
        Text(text)
            .font(.caption)
            .padding(.horizontal, 7)
            .padding(.vertical, 2)
            .background(SylvraColor.brandPrimary.opacity(0.14), in: Capsule())
            .foregroundStyle(SylvraColor.brandPrimary)
    }
}
