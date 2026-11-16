import DesignSystem
import SwiftUI
import SylvraCore

/// The sidebar content while a repository is open (container): all its open pull requests,
/// searched on GitHub and loaded page by page.
struct RepositoryBrowserContent<RowMenu: View>: View {
    @Bindable var model: InboxScreenModel
    let browser: RepositoryBrowserModel
    let rowMenu: (PullRequestSummary) -> RowMenu

    /// Reload when the repository, the search or the hidden authors change.
    private struct LoadKey: Equatable {
        let repository: String
        let search: String
        let hiddenAuthors: [String]
    }

    var body: some View {
        Section {
            header
        }
        .task(id: loadKey) { await load() }

        switch browser.loadState {
        case .loading:
            HStack {
                Spacer()
                ProgressView().controlSize(.small)
                Spacer()
            }
            .selectionDisabled()
        case .failed(let message):
            Section {
                VStack(alignment: .leading, spacing: 6) {
                    Label("Couldn't load pull requests", systemImage: "exclamationmark.triangle")
                    Text(message).font(.caption).foregroundStyle(.secondary).textSelection(.enabled)
                    Button("Try again") { Task { await load() } }
                }
                .selectionDisabled()
            }
        case .loaded:
            loadedContent
        }
    }

    @ViewBuilder private var loadedContent: some View {
        let groups = model.browserGroups
        if groups.isEmpty {
            Text(browser.searchText.isEmpty ? "No open pull requests" : "No matching pull requests")
                .foregroundStyle(.secondary)
                .selectionDisabled()
        }
        ForEach(groups, id: \.title) { group in
            Section {
                ForEach(group.pullRequests) { pullRequest in
                    InboxRowView(
                        pullRequest: pullRequest,
                        isWaitingOnOthers: group.title == String(localized: "Waiting on others")
                    )
                    .tag(pullRequest.id)
                    .contextMenu { rowMenu(pullRequest) }
                }
            } header: {
                SectionHeading(
                    title: group.title, count: group.pullRequests.count,
                    isProminent: group.title == String(localized: "Waiting for you"))
            }
        }
        if browser.canLoadMore {
            HStack(spacing: 6) {
                if browser.isLoadingMore { ProgressView().controlSize(.small) }
                Button("Load more (\(browser.pullRequests.count) of \(browser.totalCount))") {
                    Task { await browser.loadMore(excludingAuthors: model.filter.preferences.hiddenAuthors) }
                }
                .buttonStyle(.link)
            }
            .font(.caption)
            .selectionDisabled()
            // Scrolling to the end loads the next page.
            .onAppear { Task { await browser.loadMore(excludingAuthors: model.filter.preferences.hiddenAuthors) } }
        }
    }

    private var header: some View {
        VStack(alignment: .leading, spacing: 4) {
            Button {
                model.closeRepository()
            } label: {
                Label("Inbox", systemImage: "chevron.left")
                    .font(.caption)
                    .foregroundStyle(SylvraColor.brandPrimary)
            }
            .buttonStyle(.plain)
            .keyboardShortcut(.escape, modifiers: [])
            .help("Back to the inbox (Esc)")
            HStack(alignment: .firstTextBaseline) {
                Text(browser.repository.name).font(.headline)
                Spacer()
                if browser.loadState == .loaded {
                    Text("\(browser.totalCount) open")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
            Text(browser.repository.owner).font(.caption).foregroundStyle(.secondary)
        }
        .padding(.vertical, 2)
        .selectionDisabled()
    }

    private var loadKey: LoadKey {
        LoadKey(
            repository: browser.repository.id, search: model.searchText.trimmingCharacters(in: .whitespaces),
            hiddenAuthors: model.filter.preferences.hiddenAuthors)
    }

    private func load() async {
        let key = loadKey
        if !key.search.isEmpty {
            // Debounce typing; the task is cancelled when the text changes.
            try? await Task.sleep(for: .milliseconds(350))
            guard !Task.isCancelled else { return }
        }
        await browser.load(matching: key.search, excludingAuthors: key.hiddenAuthors)
    }
}
