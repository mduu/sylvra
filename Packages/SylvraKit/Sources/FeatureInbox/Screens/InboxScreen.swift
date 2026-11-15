import DesignSystem
import SwiftUI
import SylvraCore

/// The inbox sidebar (container): owns loading and periodic refresh.
public struct InboxScreen: View {
    @Bindable private var model: InboxScreenModel
    @Binding private var selection: PullRequestSummary?

    public init(model: InboxScreenModel, selection: Binding<PullRequestSummary?>) {
        self.model = model
        self._selection = selection
    }

    public var body: some View {
        List(selection: $selection) {
            ForEach(model.visibleSections, id: \.section) { entry in
                Section {
                    ForEach(entry.pullRequests) { pullRequest in
                        InboxRowView(pullRequest: pullRequest).tag(pullRequest)
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
        .searchable(text: $model.searchText, placement: .sidebar, prompt: Text("Search PRs"))
        .overlay { overlay }
        .task { await model.keepRefreshing() }
        .toolbar {
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

    @ViewBuilder private var overlay: some View {
        switch model.loadState {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView {
                Label("Couldn't load pull requests", systemImage: "exclamationmark.triangle")
            } description: {
                Text(message)
            } actions: {
                Button("Try again") { Task { await model.refresh() } }
            }
        case .loaded where model.snapshot.isEmpty:
            ContentUnavailableView(
                "Nothing to review",
                systemImage: "leaf",
                description: Text("Enjoy the quiet.")
            )
        default:
            EmptyView()
        }
    }
}

#Preview {
    @Previewable @State var selection: PullRequestSummary?
    NavigationSplitView {
        InboxScreen(model: InboxScreenModel(loader: DemoInboxLoader()), selection: $selection)
    } detail: {
        Text(selection?.title ?? "–")
    }
}
