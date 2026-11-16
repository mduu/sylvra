import AppKit
import DesignSystem
import SwiftUI
import SylvraCore

/// The PR column (container): loads details for the selected PR and handles copy / open actions.
/// Slots provided by the app (slices don't import each other): `summary` (pinned above the tabs, e.g. the AI
/// summary), `overviewTop` (e.g. the change map) and `files` (file navigator). Selecting a commit reviews it on
/// its own (`selectCommit`, `nil` = all changes).
public struct PullRequestScreen<Files: View, OverviewTop: View, Summary: View>: View {
    @Bindable private var model: PullRequestScreenModel
    private let pullRequest: PullRequestSummary?
    private let files: Files
    private let overviewTop: OverviewTop
    private let summary: Summary
    private let selectedCommitSHA: String?
    private let selectCommit: ((Commit?) -> Void)?
    private let showInCode: ((String, Int?) -> Void)?
    @Environment(\.openURL) private var openURL

    public init(
        model: PullRequestScreenModel, pullRequest: PullRequestSummary?,
        selectedCommitSHA: String? = nil, selectCommit: ((Commit?) -> Void)? = nil,
        showInCode: ((String, Int?) -> Void)? = nil,
        @ViewBuilder summary: () -> Summary,
        @ViewBuilder overviewTop: () -> OverviewTop,
        @ViewBuilder files: () -> Files
    ) {
        self.summary = summary()
        self.model = model
        self.pullRequest = pullRequest
        self.selectedCommitSHA = selectedCommitSHA
        self.selectCommit = selectCommit
        self.showInCode = showInCode
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
        .task(id: pullRequest?.id) { await model.load(pullRequest?.id) }
        .sheet(item: $model.openedCheck) { check in
            CheckReportSheet(
                check: check, load: { try await model.report(for: check) }, openOnGitHub: { open(check.url) })
        }
    }

    /// Header, summary and tabs stay at the top; only the tab content scrolls.
    private func content(_ detail: PullRequestDetail) -> some View {
        VStack(alignment: .leading, spacing: 0) {
            VStack(alignment: .leading, spacing: 12) {
                PullRequestHeaderView(detail: detail) { open(detail.summary.url) }
                summary
                Picker("Section", selection: $model.tab) {
                    Text("Overview").tag(PullRequestScreenModel.Tab.overview)
                    Text("Files \(detail.changedFiles)").tag(PullRequestScreenModel.Tab.files)
                    Text("Commits \(detail.commits.count)").tag(PullRequestScreenModel.Tab.commits)
                    Text("Checks \(detail.checks.count)").tag(PullRequestScreenModel.Tab.checks)
                    Text("Comments \(detail.commentCount)").tag(PullRequestScreenModel.Tab.comments)
                }
                .pickerStyle(.segmented)
                .labelsHidden()
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
        switch model.tab {
        case .overview:
            overviewTop
            OverviewView(detail: detail, open: open)
        case .files:
            files
        case .commits:
            commitList(detail)
        case .comments:
            DiscussionListView(
                items: detail.discussion, filter: $model.discussionFilter, showInCode: showInCode, open: open)
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

extension PullRequestScreen where Files == EmptyView, OverviewTop == EmptyView, Summary == EmptyView {
    public init(model: PullRequestScreenModel, pullRequest: PullRequestSummary?) {
        self.init(
            model: model, pullRequest: pullRequest, summary: { EmptyView() }, overviewTop: { EmptyView() },
            files: { EmptyView() })
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
