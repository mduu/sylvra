import SwiftUI
import SylvraCore

/// The diff of the selected pull request (container).
///
/// Slots provided by the app (slices don't import each other):
/// - `lineAccessory` renders content below a line (e.g. review threads and the comment composer),
/// - `onStartComment` is called with the location and its text when the reviewer starts a comment
///   (gutter `+` or click on a line number; ⇧-click extends the range on the same side).
public struct DiffScreen<LineAccessory: View>: View {
    @Bindable private var model: DiffScreenModel
    private let pullRequestID: PullRequestID?
    private let headSHA: String?
    private let lineAccessory: (CodeLocation) -> LineAccessory
    private let onStartComment: ((CodeLocation, String) -> Void)?
    @State private var commentAnchor: CodeLocation?

    public init(
        model: DiffScreenModel,
        pullRequestID: PullRequestID?,
        headSHA: String?,
        @ViewBuilder lineAccessory: @escaping (CodeLocation) -> LineAccessory,
        onStartComment: ((CodeLocation, String) -> Void)? = nil
    ) {
        self.model = model
        self.pullRequestID = pullRequestID
        self.headSHA = headSHA
        self.lineAccessory = lineAccessory
        self.onStartComment = onStartComment
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
                                    DiffFileBodyView(
                                        path: file.path,
                                        hunks: model.hunks(for: file),
                                        layout: model.layout,
                                        accessory: lineAccessory,
                                        onComment: onStartComment == nil
                                            ? nil
                                            : { side, line, extends in
                                                startComment(path: file.path, side: side, line: line, extends: extends)
                                            }
                                    )
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

    private func startComment(path: String, side: CodeLocation.Side, line: Int, extends: Bool) {
        var location = CodeLocation(path: path, line: line, side: side)
        if extends, let anchor = commentAnchor, anchor.path == path, anchor.side == side {
            let lines = anchor.lines
            location = CodeLocation(
                path: path, line: max(line, lines.upperBound), side: side, startLine: min(line, lines.lowerBound))
        }
        commentAnchor = location
        onStartComment?(location, model.text(at: location))
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

extension DiffScreen where LineAccessory == EmptyView {
    public init(model: DiffScreenModel, pullRequestID: PullRequestID?, headSHA: String?) {
        self.init(model: model, pullRequestID: pullRequestID, headSHA: headSHA) { _ in EmptyView() }
    }
}
