import AppKit
import DesignSystem
import SwiftUI
import SylvraCore

/// The PR column (container): loads details for the selected PR and handles copy / open actions.
/// Slots provided by the app (slices don't import each other): `summary` (pinned above the tabs, e.g. the AI
/// summary), `overviewTop` (e.g. the change map), `files` (file navigator) and `conversation` (the comments on
/// the pull request itself, with writing). Selecting a commit reviews it on its own (`selectCommit`, `nil` = all
/// changes). `openPullRequest` opens another layer of the pull request's stack (`nil` hides the stack bar).
/// `delivery` is the Delivery tab of a merged pull request (`nil`: no such tab).
/// The details reload every minute and with the header's refresh button; `refreshOthers` reloads what the app
/// shows next to them (comments, threads, new commits).
public struct PullRequestScreen<Files: View, OverviewTop: View, Summary: View, Conversation: View>: View {
    @Bindable private var model: PullRequestScreenModel
    private let pullRequest: PullRequestSummary?
    private let files: Files
    private let overviewTop: OverviewTop
    private let summary: Summary
    private let conversation: Conversation
    private let selectedCommitSHA: String?
    private let selectCommit: ((Commit?) -> Void)?
    private let showInCode: ((String, Int?) -> Void)?
    private let openPullRequest: ((PullRequestSummary) -> Void)?
    private let refreshOthers: (() async -> Void)?
    private let delivery: AnyView?
    @Environment(\.openURL) private var openURL

    public init(
        model: PullRequestScreenModel, pullRequest: PullRequestSummary?,
        selectedCommitSHA: String? = nil, selectCommit: ((Commit?) -> Void)? = nil,
        showInCode: ((String, Int?) -> Void)? = nil,
        openPullRequest: ((PullRequestSummary) -> Void)? = nil,
        refreshOthers: (() async -> Void)? = nil,
        delivery: AnyView? = nil,
        @ViewBuilder summary: () -> Summary,
        @ViewBuilder overviewTop: () -> OverviewTop,
        @ViewBuilder files: () -> Files,
        @ViewBuilder conversation: () -> Conversation
    ) {
        self.summary = summary()
        self.conversation = conversation()
        self.model = model
        self.pullRequest = pullRequest
        self.selectedCommitSHA = selectedCommitSHA
        self.selectCommit = selectCommit
        self.showInCode = showInCode
        self.openPullRequest = openPullRequest
        self.refreshOthers = refreshOthers
        self.delivery = delivery
        self.overviewTop = overviewTop()
        self.files = files()
    }

    public var body: some View {
        Group {
            if let detail = model.detail {
                content(detail)
            } else {
                placeholder
            }
        }
        .frame(maxWidth: .infinity, maxHeight: .infinity)
        .background(SylvraColor.surfacePrimary)
        .task(id: pullRequest?.id) {
            await model.load(pullRequest?.id)
            await model.keepRefreshing()
        }
        .sheet(isPresented: $model.isMergeSheetPresented) {
            if let detail = model.detail, let action = model.mergeAction {
                MergeSheet(model: model, detail: detail, action: action)
            }
        }
        .sheet(item: $model.openedCheck) { check in
            CheckReportSheet(
                check: check, load: { try await model.report(for: check) }, openOnGitHub: { open(check.url) })
        }
    }

    /// Header, summary and tabs stay at the top; only the tab content scrolls.
    private func content(_ detail: PullRequestDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                PullRequestHeaderView(
                    detail: detail, isRefreshing: model.isRefreshing, lastUpdated: model.lastUpdated,
                    refresh: { Task { await refresh() } }, mergeAction: model.mergeAction,
                    merge: { model.startMerge() }, openOnGitHub: { open(detail.summary.url) })
                if let stack = model.stack, let openPullRequest {
                    StackBarView(status: stack, open: openPullRequest)
                }
                summary
                // All tabs side by side; narrow columns get smaller text or symbols, never a menu.
                SectionTabBar(
                    items: PullRequestTabItem.items(for: detail, hasDelivery: delivery != nil).map(\.barItem),
                    selection: $model.tab)
            }
            .padding([.horizontal, .top], 16)
            .padding(.bottom, 10)
            Divider().opacity(0.5)
            ScrollView {
                VStack(alignment: .leading, spacing: 16) {
                    tabContent(detail)
                }
                .padding(16)
                .animation(.snappy, value: model.tab)
            }
        }
    }

    @ViewBuilder private func tabContent(_ detail: PullRequestDetail) -> some View {
        // The Delivery tab only exists for merged pull requests: another one shows its overview instead.
        let hasDelivery = delivery != nil && detail.state == .merged
        switch model.tab == .delivery && !hasDelivery ? .overview : model.tab {
        case .delivery:
            delivery
        case .overview:
            overviewTop
            OverviewView(detail: detail, open: open)
        case .files:
            files
        case .commits:
            commitList(detail)
        case .comments:
            Picker("Show", selection: $model.discussionFilter) {
                ForEach(DiscussionFilter.allCases) { Text($0.title).tag($0) }
            }
            .pickerStyle(.segmented)
            .labelsHidden()
            .controlSize(.small)
            if model.discussionFilter == .conversation, Conversation.self != EmptyView.self {
                conversation
            } else {
                DiscussionListView(
                    items: model.discussionFilter.apply(detail.discussion), showInCode: showInCode,
                    toggleResolved: model.resolveThread == nil
                        ? nil : { item in Task { await model.toggleResolved(item) } },
                    open: open)
            }
        case .checks:
            LazyVStack(alignment: .leading, spacing: 6) {
                ForEach(detail.checks) { check in
                    CheckRowView(check: check, showReport: { model.openedCheck = check }, open: { open(check.url) })
                }
                if detail.checks.isEmpty { Text("No checks").foregroundStyle(.secondary) }
            }
        }
    }

    /// Commits oldest first; selecting one shows only its changes in the diff.
    private func commitList(_ detail: PullRequestDetail) -> some View {
        LazyVStack(alignment: .leading, spacing: 8) {
            if let selectCommit {
                AllChangesRowView(isSelected: selectedCommitSHA == nil) { selectCommit(nil) }
                Text("Select a commit to review it on its own (⌥] / ⌥[ step through).")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                Divider()
            }
            ForEach(Array(detail.commits.enumerated()), id: \.element.id) { index, commit in
                CommitRowView(
                    commit: commit,
                    number: selectCommit == nil ? nil : index + 1,
                    isSelected: commit.sha == selectedCommitSHA,
                    select: selectCommit.map { select in { select(commit) } },
                    copySHA: { copy($0 ? commit.sha : commit.shortSHA) },
                    open: { open(commit.url ?? commitURL(detail, commit)) }
                )
                Divider()
            }
        }
    }

    @ViewBuilder private var placeholder: some View {
        switch model.loadState {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load pull request", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.load(pullRequest?.id) } }
            }
        default:
            ContentUnavailableView(
                "No pull request selected", systemImage: "arrow.triangle.pull",
                description: Text("Pick one from the inbox."))
        }
    }

    // MARK: - Side effects

    private func refresh() async {
        await model.refresh()
        await refreshOthers?()
    }

    private func open(_ url: URL?) {
        if let url { openURL(url) }
    }

    private func copy(_ text: String) {
        NSPasteboard.general.clearContents()
        NSPasteboard.general.setString(text, forType: .string)
    }

    private func commitURL(_ detail: PullRequestDetail, _ commit: Commit) -> URL? {
        URL(
            string: "https://github.com/\(detail.summary.id.owner)/\(detail.summary.id.repository)/commit/\(commit.sha)"
        )
    }
}

extension PullRequestScreen
where Files == EmptyView, OverviewTop == EmptyView, Summary == EmptyView, Conversation == EmptyView {
    public init(model: PullRequestScreenModel, pullRequest: PullRequestSummary?) {
        self.init(
            model: model, pullRequest: pullRequest, summary: { EmptyView() }, overviewTop: { EmptyView() },
            files: { EmptyView() }, conversation: { EmptyView() })
    }
}

#Preview {
    PullRequestScreen(
        model: PullRequestScreenModel(loader: DemoPullRequestDetailLoader()),
        pullRequest: DemoPullRequestDetailLoader.detail(for: .init(owner: "acme", repository: "billing", number: 1234))
            .summary
    )
    .frame(width: 340, height: 800)
}
