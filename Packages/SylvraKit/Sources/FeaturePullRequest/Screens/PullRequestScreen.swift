import AppKit
import DesignSystem
import SwiftUI
import SylvraCore

/// The PR column (container): loads details for the selected PR and handles copy / open actions.
/// Slots provided by the app (slices don't import each other): `files` (file navigator) and `overviewTop`
/// (e.g. the change map). Selecting a commit reviews it on its own (`selectCommit`, `nil` = all changes).
public struct PullRequestScreen<Files: View, OverviewTop: View>: View {
    @Bindable private var model: PullRequestScreenModel
    private let pullRequest: PullRequestSummary?
    private let files: Files
    private let overviewTop: OverviewTop
    private let selectedCommitSHA: String?
    private let selectCommit: ((Commit?) -> Void)?
    @Environment(\.openURL) private var openURL

    public init(
        model: PullRequestScreenModel, pullRequest: PullRequestSummary?,
        selectedCommitSHA: String? = nil, selectCommit: ((Commit?) -> Void)? = nil,
        @ViewBuilder overviewTop: () -> OverviewTop,
        @ViewBuilder files: () -> Files
    ) {
        self.model = model
        self.pullRequest = pullRequest
        self.selectedCommitSHA = selectedCommitSHA
        self.selectCommit = selectCommit
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

    private func content(_ detail: PullRequestDetail) -> some View {
        ScrollView {
            VStack(alignment: .leading, spacing: 16) {
                PullRequestHeaderView(detail: detail) { open(detail.summary.url) }
                Picker("Section", selection: $model.tab) {
                    Text("Overview").tag(PullRequestScreenModel.Tab.overview)
                    Text("Files \(detail.changedFiles)").tag(PullRequestScreenModel.Tab.files)
                    Text("Commits \(detail.commits.count)").tag(PullRequestScreenModel.Tab.commits)
                    Text("Checks \(detail.checks.count)").tag(PullRequestScreenModel.Tab.checks)
                }
                .pickerStyle(.segmented)
                .labelsHidden()

                switch model.tab {
                case .overview:
                    overviewTop
                    OverviewView(detail: detail, open: open)
                case .files:
                    files
                case .commits:
                    commitList(detail)
                case .checks:
                    LazyVStack(alignment: .leading, spacing: 6) {
                        ForEach(detail.checks) { check in
                            CheckRowView(
                                check: check, showReport: { model.openedCheck = check }, open: { open(check.url) })
                        }
                        if detail.checks.isEmpty { Text("No checks").foregroundStyle(.secondary) }
                    }
                }
            }
            .padding(16)
            .animation(.snappy, value: model.tab)
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

extension PullRequestScreen where Files == EmptyView, OverviewTop == EmptyView {
    public init(model: PullRequestScreenModel, pullRequest: PullRequestSummary?) {
        self.init(model: model, pullRequest: pullRequest) {
            EmptyView()
        } files: {
            EmptyView()
        }
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
