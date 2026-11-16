import DesignSystem
import SwiftUI
import SylvraCore

/// The inbox sidebar (container): owns loading and periodic refresh.
public struct InboxScreen: View {
    @Bindable private var model: InboxScreenModel
    @Binding private var selection: PullRequestID?

    /// Selection is the PR's ID, so it survives refreshes that change the summary (CI state, timestamps).
    public init(model: InboxScreenModel, selection: Binding<PullRequestID?>) {
        self.model = model
        self._selection = selection
    }

    public var body: some View {
        List(selection: $selection) {
            if let browser = model.browser {
                RepositoryBrowserContent(model: model, browser: browser, rowMenu: rowMenu)
            } else {
                inboxContent
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(SylvraColor.surfaceSidebar)
        .searchable(text: $model.searchText, placement: .sidebar, prompt: searchPrompt)
        .safeAreaInset(edge: .top, spacing: 0) {
            if !model.snapshot.isEmpty || model.browser != nil {
                InboxFilterBar(
                    filter: model.filter, authors: model.authors,
                    hiddenCount: model.browser == nil ? model.hiddenCount : model.browserHiddenCount,
                    toggle: model.toggle, showOnlyAuthor: model.showOnly(author:), clear: model.clearTemporaryFilters,
                    updatePreferences: model.updatePreferences)
            }
        }
        .overlay { overlay }
        .safeAreaInset(edge: .bottom) {
            VStack(spacing: 0) {
                if case .failed = model.loadState, !model.snapshot.isEmpty {
                    Label("Offline — showing the last loaded pull requests", systemImage: "wifi.exclamationmark")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(6)
                }
                if model.snapshot.isRestrictedBySSO == true {
                    ssoHint
                }
            }
        }
        .sheet(isPresented: $model.isChoosingRepositories) {
            InboxRepositoriesSheet(model: model)
        }
        .task { await model.keepRefreshing() }
        .toolbar {
            ToolbarItem {
                Button {
                    Task {
                        await model.refresh()
                        await model.browser?.load(
                            matching: model.browser?.searchText ?? "",
                            excludingAuthors: model.filter.preferences.hiddenAuthors)
                    }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    @ViewBuilder private func rowMenu(_ pullRequest: PullRequestSummary) -> some View {
        let login = pullRequest.author.login
        Button("Show only PRs by \(login)", systemImage: "person") { model.showOnly(author: login) }
        Button("Hide PRs by \(login)", systemImage: "eye.slash") { model.updatePreferences { $0.hideAuthor(login) } }
        if let url = pullRequest.url {
            Divider()
            Link(destination: url) { Label("Open on GitHub", systemImage: "safari") }
        }
    }

    private var ssoHint: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "lock.shield").foregroundStyle(SylvraColor.accentGold)
            Text(
                // swiftlint:disable:next line_length
                "Some organizations hide their pull requests: your GitHub CLI token isn't authorized for their single sign-on. Run `gh auth refresh` or authorize “GitHub CLI” under github.com → Settings → Applications."
            )
            .fixedSize(horizontal: false, vertical: true)
        }
        .font(.caption)
        .foregroundStyle(.secondary)
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(SylvraColor.accentGold.opacity(0.08))
    }

    private var searchPrompt: Text {
        if let browser = model.browser {
            return Text("Search in \(browser.repository.name)")
        }
        return Text("Search PRs")
    }

    @ViewBuilder private var inboxContent: some View {
        ForEach(model.visibleSections, id: \.section) { entry in
            Section(isExpanded: expansion(entry.section.rawValue)) {
                ForEach(entry.pullRequests) { pullRequest in
                    InboxRowView(pullRequest: pullRequest)
                        .tag(pullRequest.id)
                        .contextMenu { rowMenu(pullRequest) }
                }
            } header: {
                HStack {
                    Text(entry.section.title)
                    Spacer()
                    Text(entry.pullRequests.count, format: .number)
                        .foregroundStyle(
                            entry.section == .requestedFromMe && !entry.pullRequests.isEmpty
                                ? AnyShapeStyle(SylvraColor.accentGold) : AnyShapeStyle(.secondary))
                }
            }
        }
        if model.repositoryLoader != nil {
            if model.loadState == .loaded, model.visibleSections.isEmpty {
                Section {
                    Label("Nothing waiting for you. Enjoy the quiet.", systemImage: "leaf")
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
            }
            repositoriesSection
        }
    }

    private func expansion(_ section: String) -> Binding<Bool> {
        Binding(get: { model.isExpanded(section) }, set: { model.setExpanded(section, $0) })
    }

    private var repositoriesSection: some View {
        Section(isExpanded: expansion("repositories")) {
            ForEach(model.scope.repositories) { repository in
                Button {
                    model.openRepository(repository)
                } label: {
                    RepositoryListRow(repository: repository, openCount: model.repositoryCounts[repository.id])
                }
                .buttonStyle(.plain)
                .selectionDisabled()
                .contextMenu {
                    Button("Remove from inbox", systemImage: "minus.circle") {
                        Task { await model.removeRepository(repository) }
                    }
                }
            }
            Button {
                model.isChoosingRepositories = true
            } label: {
                Label("Add repository", systemImage: "plus")
                    .foregroundStyle(SylvraColor.brandPrimary)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.plain)
            .selectionDisabled()
            if model.scope.isAll {
                Text("Add the repositories you work in: browse all their open pull requests here.")
                    .font(.caption)
                    .foregroundStyle(.secondary)
                    .selectionDisabled()
            }
        } header: {
            Text("Repositories")
        }
    }

    @ViewBuilder private var overlay: some View {
        switch model.loadState {
        case .loading where model.browser == nil:
            ProgressView()
        case .failed(let message) where model.snapshot.isEmpty && model.browser == nil:
            ContentUnavailableView {
                Label("Couldn't load pull requests", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message).textSelection(.enabled)
            } actions: {
                Button("Try again") { Task { await model.refresh() } }
                if model.repositorySearcher != nil, model.scope.isAll {
                    Button("Choose repositories…") { model.isChoosingRepositories = true }
                        .help("Searching fewer repositories helps when your organizations are large")
                }
            }
        case .loaded where model.snapshot.isEmpty && model.repositoryLoader == nil && model.browser == nil:
            ContentUnavailableView {
                Label("Nothing to review", systemImage: "leaf")
            } description: {
                Text(
                    model.scope.isAll
                        ? "Enjoy the quiet." : "Add repositories to see your teams' pull requests here.")
            } actions: {
                if model.repositorySearcher != nil {
                    Button("Add repository…", systemImage: "plus") { model.isChoosingRepositories = true }
                        .buttonStyle(.borderedProminent)
                        .tint(SylvraColor.brandPrimary)
                }
            }
        default:
            EmptyView()
        }
    }
}

#Preview {
    @Previewable @State var selection: PullRequestID?
    NavigationSplitView {
        InboxScreen(model: InboxScreenModel(loader: DemoInboxLoader()), selection: $selection)
    } detail: {
        Text(selection?.description ?? "–")
    }
}
