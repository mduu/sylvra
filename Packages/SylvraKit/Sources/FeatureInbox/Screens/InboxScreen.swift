import DesignSystem
import SwiftUI
import SylvraCore

/// The inbox sidebar (container): owns loading and periodic refresh.
public struct InboxScreen: View {
    @Bindable var model: InboxScreenModel
    @Binding private var selection: PullRequestID?
    /// To-dos just checked off: they stay a moment, checked, before they leave the list.
    @State var completing: Set<PullRequestID> = []

    /// Selection is the PR's ID, so it survives refreshes that change the summary (CI state, timestamps).
    public init(model: InboxScreenModel, selection: Binding<PullRequestID?>) {
        self.model = model
        self._selection = selection
    }

    public var body: some View {
        List(selection: $selection) {
            // The to-do list stays on top, also while a repository is open.
            let todos = model.visibleTodos
            if !todos.isEmpty { todoSection(todos) }
            if let browser = model.browser {
                RepositoryBrowserContent(model: model, browser: browser, rowMenu: rowMenu)
            } else {
                inboxContent
            }
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(SylvraColor.surfaceSidebar)
        .safeAreaInset(edge: .top, spacing: 0) {
            VStack(spacing: 0) {
                InboxSearchField(text: $model.searchText, prompt: searchPrompt)
                if !model.snapshot.isEmpty || model.browser != nil {
                    InboxFilterBar(
                        filter: model.filter, authors: model.authors,
                        hiddenCount: model.browser == nil ? model.hiddenCount : model.browserHiddenCount,
                        toggle: model.toggle, showOnlyAuthor: model.showOnly(author:),
                        clear: model.clearTemporaryFilters, updatePreferences: model.updatePreferences)
                }
            }
            .background(SylvraColor.surfaceSidebar)
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
                    Task { await model.refreshAll() }
                } label: {
                    if model.isRefreshing {
                        ProgressView().controlSize(.small)
                    } else {
                        Label("Refresh", systemImage: "arrow.clockwise")
                    }
                }
                .help(model.isRefreshing ? "Refreshing…" : "Refresh")
                .keyboardShortcut("r", modifiers: .command)
            }
        }
    }

    @ViewBuilder func rowMenu(_ pullRequest: PullRequestSummary) -> some View {
        let login = pullRequest.author.login
        if model.isTodo(pullRequest.id) {
            Button("Remove from To-Do", systemImage: "minus.circle") { removeTodo(pullRequest.id) }
        } else {
            Button("Add to To-Do", systemImage: "checklist") {
                withAnimation(.snappy) { model.addTodo(pullRequest) }
            }
        }
        Divider()
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

    private var searchPrompt: String {
        if let browser = model.browser {
            return String(localized: "Search in \(browser.repository.name)")
        }
        return String(localized: "Search PRs")
    }

    /// Open work first, then the repositories, then what was closed recently (history at the bottom).
    @ViewBuilder private var inboxContent: some View {
        let sections = model.visibleSections
        ForEach(sections.filter { $0.section != .recentlyClosed }, id: \.section, content: sectionView)
        if model.repositoryLoader != nil {
            if model.loadState == .loaded, sections.isEmpty, model.visibleTodos.isEmpty {
                Section {
                    Label("Nothing waiting for you. Enjoy the quiet.", systemImage: "leaf")
                        .foregroundStyle(.secondary)
                        .selectionDisabled()
                }
            }
            repositoriesSection
        }
        ForEach(sections.filter { $0.section == .recentlyClosed }, id: \.section, content: sectionView)
    }

    private func sectionView(_ entry: (section: InboxSection, pullRequests: [PullRequestSummary])) -> some View {
        Section(isExpanded: expansion(entry.section.rawValue)) {
            ForEach(entry.pullRequests) { pullRequest in
                InboxRowView(
                    pullRequest: pullRequest,
                    isWaitingOnOthers: InboxScreenModel.showsWaiting(pullRequest, in: entry.section),
                    delivery: model.deliveryBadge?(pullRequest.id)
                )
                .tag(pullRequest.id)
                .contextMenu { rowMenu(pullRequest) }
            }
        } header: {
            SectionHeading(
                title: entry.section.title, count: entry.pullRequests.count,
                isProminent: entry.section == .requestedFromMe)
        }
    }

    func expansion(_ section: String) -> Binding<Bool> {
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
            if model.scope.isAll {
                Text("Repositories")
            } else {
                SectionHeading(
                    title: String(localized: "Repositories"), count: model.scope.repositories.count)
            }
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
