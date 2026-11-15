import SwiftUI
import SylvraCore

/// The diff of the selected pull request (container).
public struct DiffScreen: View {
    @Bindable private var model: DiffScreenModel
    private let pullRequestID: PullRequestID?
    private let headSHA: String?

    public init(model: DiffScreenModel, pullRequestID: PullRequestID?, headSHA: String?) {
        self.model = model
        self.pullRequestID = pullRequestID
        self.headSHA = headSHA
    }

    public var body: some View {
        content
            .task(id: "\(pullRequestID?.description ?? "")@\(headSHA ?? "")") {
                await model.load(pullRequestID, headSHA: headSHA)
            }
            .toolbar {
                ToolbarItemGroup {
                    Picker("Layout", selection: $model.layout) {
                        Text("Side by side").tag(DiffScreenModel.Layout.sideBySide)
                        Text("Inline").tag(DiffScreenModel.Layout.inline)
                    }
                    .pickerStyle(.segmented)
                    .help("Diff layout (⌘⌥1 / ⌘⌥2)")
                    Picker(
                        "Scope",
                        selection: Binding(get: { model.scope }, set: { scope in Task { await model.setScope(scope) } })
                    ) {
                        Text("Focused").tag(DiffScreenModel.Scope.focused)
                        Text("Full file").tag(DiffScreenModel.Scope.fullFile)
                    }
                    .pickerStyle(.segmented)
                }
            }
    }

    @ViewBuilder private var content: some View {
        if model.diff != nil {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(model.orderedFiles) { file in
                            Section {
                                if !model.isCollapsed(file) {
                                    DiffFileBodyView(hunks: model.hunks(for: file), layout: model.layout)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            } header: {
                                DiffFileHeaderView(
                                    file: file,
                                    isViewed: model.isViewed(file.path),
                                    isCollapsed: model.isCollapsed(file),
                                    toggleCollapsed: { withAnimation(.snappy) { model.toggleExpanded(file.path) } },
                                    toggleViewed: { Task { await model.toggleViewed(file.path) } }
                                )
                                .id(file.path)
                            }
                        }
                    }
                    .animation(.snappy, value: model.layout)
                }
                .onChange(of: model.selectedPath) { _, path in
                    guard let path else { return }
                    withAnimation(.snappy) { proxy.scrollTo(path, anchor: .top) }
                }
            }
        } else {
            placeholder
        }
    }

    @ViewBuilder private var placeholder: some View {
        switch model.loadState {
        case .loading:
            ProgressView()
        case .failed(let message):
            ContentUnavailableView(
                "Couldn't load diff", systemImage: "exclamationmark.triangle", description: Text(message))
        default:
            ContentUnavailableView("No diff", systemImage: "plus.forwardslash.minus")
        }
    }
}
