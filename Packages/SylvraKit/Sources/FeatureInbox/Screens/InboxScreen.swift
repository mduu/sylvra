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
            ForEach(model.visibleSections, id: \.section) { entry in
                Section {
                    ForEach(entry.pullRequests) { pullRequest in
                        InboxRowView(pullRequest: pullRequest).tag(pullRequest.id)
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
        }
        .listStyle(.sidebar)
        .scrollContentBackground(.hidden)
        .background(SylvraColor.surfaceSidebar)
        .searchable(text: $model.searchText, placement: .sidebar, prompt: Text("Search PRs"))
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
                if model.repositorySearcher != nil {
                    scopeFooter
                }
            }
        }
        .sheet(isPresented: $model.isChoosingRepositories) {
            InboxRepositoriesSheet(model: model)
        }
        .task { await model.keepRefreshing() }
        .toolbar {
            if model.repositorySearcher != nil {
                ToolbarItem {
                    Button {
                        model.isChoosingRepositories = true
                    } label: {
                        Label(
                            "Inbox repositories",
                            systemImage: model.scope.isAll
                                ? "line.3.horizontal.decrease.circle" : "line.3.horizontal.decrease.circle.fill")
                    }
                    .help("Choose the repositories your inbox searches")
                }
            }
            ToolbarItem {
                Button {
                    Task { await model.refresh() }
                } label: {
                    Label("Refresh", systemImage: "arrow.clockwise")
                }
                .keyboardShortcut("r", modifiers: .command)
            }
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

    private var scopeFooter: some View {
        Button {
            model.isChoosingRepositories = true
        } label: {
            HStack(spacing: 6) {
                Image(systemName: "square.stack.3d.up")
                Text(
                    model.scope.isAll
                        ? String(localized: "All repositories")
                        : String(localized: "\(model.scope.repositories.count) repositories"))
                Spacer()
                Text("Edit").foregroundStyle(SylvraColor.brandPrimary)
            }
            .font(.caption)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 12)
            .padding(.vertical, 8)
            .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .background(SylvraColor.surfaceSidebar)
        .help("Choose the repositories your inbox searches")
    }

    @ViewBuilder private var overlay: some View {
        switch model.loadState {
        case .loading:
            ProgressView()
        case .failed(let message) where model.snapshot.isEmpty:
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
        case .loaded where model.snapshot.isEmpty:
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
