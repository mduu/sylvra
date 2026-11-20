import SwiftUI
import SylvraCore

/// The diff of the selected pull request (container).
///
/// Slots provided by the app (slices don't import each other):
/// - `lineAccessory` renders content below a line (e.g. review threads and the comment composer),
/// - `onStartComment` is called with the location and its text when the reviewer starts a comment
///   (gutter `+` or click on a line number; ⇧-click extends the range on the same side),
/// - `onAskAI` opens a chat about code selected with the mouse (location and selected text),
/// - `openInIDE` opens a line in the reviewer's IDE (gutter button on hover, right-click menu).
public struct DiffScreen<LineAccessory: View>: View {
    @Bindable private var model: DiffScreenModel
    private let pullRequestID: PullRequestID?
    private let headSHA: String?
    private let lineAccessory: (CodeLocation) -> LineAccessory
    private let onStartComment: ((CodeLocation, String) -> Void)?
    private let onAskAI: ((CodeLocation, String) -> Void)?
    private let openInIDE: DiffOpenInIDE?
    /// Reloads the PR after a push (details, head SHA → diff); `nil` reloads only the diff.
    private let onRefresh: (() async -> Void)?
    /// Whether a detected push may reload right away (not while the reviewer writes a comment); otherwise a
    /// banner offers *Refresh*.
    private let refreshesAutomatically: () -> Bool
    @State private var diffIsWide = true
    @State private var diffWidth = DiffWidth()
    @State private var rowCache = DiffRowCache()
    @State private var commentAnchor: CodeLocation?
    @State private var textSelection = DiffTextSelectionController()
    /// Only used to scroll while a selection is dragged past an edge (offsets, no IDs: see below).
    @State private var scrollPosition = ScrollPosition()
    @State private var scrollGeometry: ScrollGeometry?

    public init(
        model: DiffScreenModel,
        pullRequestID: PullRequestID?,
        headSHA: String?,
        @ViewBuilder lineAccessory: @escaping (CodeLocation) -> LineAccessory,
        onStartComment: ((CodeLocation, String) -> Void)? = nil,
        onAskAI: ((CodeLocation, String) -> Void)? = nil,
        openInIDE: DiffOpenInIDE? = nil,
        onRefresh: (() async -> Void)? = nil,
        refreshesAutomatically: @escaping () -> Bool = { false }
    ) {
        self.model = model
        self.pullRequestID = pullRequestID
        self.headSHA = headSHA
        self.lineAccessory = lineAccessory
        self.onStartComment = onStartComment
        self.onAskAI = onAskAI
        self.openInIDE = openInIDE
        self.onRefresh = onRefresh
        self.refreshesAutomatically = refreshesAutomatically
    }

    public var body: some View {
        content
            .safeAreaInset(edge: .top) {
                if model.isSearchPresented {
                    DiffSearchPanel(model: model)
                        .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.isSearchPresented)
            .safeAreaInset(edge: .top) {
                if let commit = model.selectedCommit, let position = model.commitPosition {
                    CommitModeBar(
                        commit: commit, number: position.number, count: position.count,
                        isLoading: model.isLoadingCommit,
                        previous: { Task { await model.selectCommit(offset: -1) } },
                        next: { Task { await model.selectCommit(offset: 1) } },
                        showAll: { Task { await model.showCommit(nil) } }
                    )
                    .transition(.move(edge: .top).combined(with: .opacity))
                }
            }
            .animation(.snappy, value: model.selectedCommit)
            .safeAreaInset(edge: .top) {
                ReviewProgressBar(
                    progress: model.progress,
                    hasNewCommits: model.hasNewCommits,
                    isShowingSinceReview: model.scope == .sinceLastReview,
                    showSinceReview: { Task { await model.setScope(.sinceLastReview) } },
                    showAll: { Task { await model.setScope(.focused) } },
                    refresh: { Task { await refresh() } }
                )
                .animation(.snappy, value: model.hasNewCommits)
            }
            .onChange(of: model.hasNewCommits) { _, hasNew in
                // A push: reload the file list, commits and diff right away unless a comment is being written.
                if hasNew, refreshesAutomatically() { Task { await refresh() } }
            }
            .task(id: pullRequestID) {
                // Watch for pushes while the PR is open.
                while !Task.isCancelled {
                    try? await Task.sleep(for: model.pollInterval)
                    await model.checkForNewCommits()
                }
            }
            .safeAreaInset(edge: .top) {
                if let error = model.lastError {
                    HStack {
                        Label(error, systemImage: "exclamationmark.triangle.fill").foregroundStyle(.red)
                        Spacer()
                        Button("Dismiss") { model.lastError = nil }.buttonStyle(.borderless)
                    }
                    .font(.callout)
                    .padding(8)
                    .background(.bar)
                }
            }
            .task(id: pullRequestID) { await model.load(pullRequestID, headSHA: headSHA) }
            .onChange(of: headSHA) { _, head in
                Task { await model.headChanged(to: head, for: pullRequestID) }
            }
            // Full file: the selected file loads when it is shown.
            .task(id: model.fullFilePath) { await model.loadFullFile() }
    }

    @ViewBuilder private var content: some View {
        if model.diff != nil {
            ScrollViewReader { proxy in
                ScrollView {
                    LazyVStack(spacing: 0, pinnedViews: .sectionHeaders) {
                        ForEach(model.shownFiles) { file in
                            Section {
                                if !model.isCollapsed(file) {
                                    fileBody(file)
                                        .transition(.opacity.combined(with: .move(edge: .top)))
                                }
                            } header: {
                                DiffFileHeaderView(
                                    file: file,
                                    isViewed: model.isViewed(file.path),
                                    isCollapsed: model.isCollapsed(file),
                                    toggleCollapsed: { withAnimation(.snappy) { model.toggleExpanded(file.path) } },
                                    toggleViewed: { Task { await model.markViewedAndContinue(file.path) } },
                                    select: { withAnimation(.snappy) { model.selectInNavigator(file.path) } },
                                    readingStep: model.readingStep(for: file.path)
                                )
                                .id(file.path)
                            }
                        }
                    }
                    // No `scrollPosition(id:)`: with pinned file headers the remembered top row was often a
                    // header, and every re-render (e.g. a refresh) jumped back to the top of that file.
                    // A new layout, scope or commit builds all rows from scratch: rows the lazy stack kept from
                    // the previous mode (and animations between modes) left files rendered in a mix of modes.
                    .id(renderMode)
                    .animation(.snappy, value: model.revealedContext)
                    .coordinateSpace(.named(DiffTextSelectionController.coordinateSpace))
                    // On the whole diff, not on a row: the lazy stack drops rows scrolled out while dragging.
                    .simultaneousGesture(
                        DragGesture(
                            minimumDistance: 3, coordinateSpace: .named(DiffTextSelectionController.coordinateSpace)
                        )
                        .onChanged { value in
                            textSelection.drag(
                                from: value.startLocation, to: value.location,
                                horizontalOffset: min(
                                    model.horizontalOffset, model.maxHorizontalOffset(diffWidth: diffWidth.value)))
                        }
                        .onEnded { _ in textSelection.endDrag() }
                    )
                }
                .scrollPosition($scrollPosition)
                .onScrollGeometryChange(for: ScrollGeometry.self) {
                    $0
                } action: { _, geometry in
                    scrollGeometry = geometry
                    textSelection.visibleRect = geometry.visibleRect
                }
                .onChange(of: renderMode) {
                    textSelection.clear()
                    guard let path = model.selectedPath else { return }
                    Task { @MainActor in proxy.scrollTo(path, anchor: .top) }
                }
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.width
                } action: { width in
                    if diffWidth.value != width { diffWidth.value = width }
                    let isWide = width >= 760  // room for two thread lanes of ~320 pt
                    if diffIsWide != isWide { diffIsWide = isWide }
                }
                .overlay(alignment: .topTrailing) {
                    if model.isLoadingScope { DiffLoadingBadge().padding(10) }
                }
                .horizontalWheelScrolling { model.scrollHorizontally(by: $0, diffWidth: diffWidth.value) }
                .overlay(alignment: .bottom) { DiffHorizontalIndicator(model: model, width: diffWidth) }
                .modifier(DiffHorizontalOffsetEnvironment(model: model, width: diffWidth))
                .environment(\.diffIsWide, diffIsWide)
                .environment(\.diffTextSelection, textSelection)
                .onAppear(perform: connectTextSelection)
                .environment(\.diffRowCache, rowCache)
                .onChange(of: pullRequestID) {
                    textSelection.clear()
                    rowCache.removeAll()
                }
                .environment(
                    \.diffSelectFinding,
                    isCommitMode
                        ? nil
                        : model.selectFinding.map { DiffFindingSelection(owner: ObjectIdentifier(model), select: $0) }
                )
                .environment(\.diffOpenInIDE, openInIDE)
                .environment(\.diffSearchQuery, model.isSearchPresented ? model.searchQuery : "")
                .environment(
                    \.diffCurrentMatch,
                    model.currentSearchMatch.map { DiffScreenModel.lineAnchor(path: $0.path, line: $0.line) }
                )
                .onChange(of: model.selectedPath) { _, path in
                    // Selected from its own header: the file is already in view.
                    if model.keepsDiffPosition {
                        model.keepsDiffPosition = false
                        return
                    }
                    guard let path, model.focusedLine?.path != path else { return }
                    withAnimation(.snappy) { proxy.scrollTo(path, anchor: .top) }
                }
                .onChange(of: model.headerRequest?.id) {
                    guard let path = model.headerRequest?.path else { return }
                    withAnimation(.snappy) { proxy.scrollTo(path, anchor: .top) }
                }
                .onChange(of: model.focusedLine?.token) {
                    guard let target = model.focusedLine else { return }
                    // Straight to the line: rows are identified by their anchors, so the lazy stack finds lines
                    // it hasn't built yet. (Scrolling to the file first made the diff jump to the file's top.)
                    Task { @MainActor in
                        withAnimation(.smooth(duration: 0.35)) {
                            proxy.scrollTo(
                                DiffScreenModel.lineAnchor(path: target.path, line: target.line), anchor: .center)
                        }
                    }
                }
            }
        } else {
            placeholder
        }
    }

    /// *Copy* and *Ask AI* on a mouse selection resolve it against the file's current hunks.
    private func connectTextSelection() {
        let hunks: (String) -> [Hunk] = { path in
            model.orderedFiles.first { $0.path == path }.map(model.hunks(for:)) ?? []
        }
        textSelection.scrollBy = { delta in
            guard let geometry = scrollGeometry else { return }
            let top = -geometry.contentInsets.top
            let bottom = geometry.contentSize.height - geometry.containerSize.height + geometry.contentInsets.bottom
            let target = min(max(geometry.contentOffset.y + delta, top), max(bottom, top))
            guard target != geometry.contentOffset.y else { return }
            scrollPosition.scrollTo(y: target)
        }
        textSelection.copy = { selection in DiffCopy.toClipboard(selection.text(in: hunks(selection.path))) }
        textSelection.askAI = onAskAI.map { onAskAI in
            { selection in
                let fileHunks = hunks(selection.path)
                guard let location = selection.location(in: fileHunks) else { return }
                onAskAI(location, selection.text(in: fileHunks))
            }
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
}

extension DiffScreen where LineAccessory == EmptyView {
    public init(model: DiffScreenModel, pullRequestID: PullRequestID?, headSHA: String?) {
        self.init(model: model, pullRequestID: pullRequestID, headSHA: headSHA) { _ in EmptyView() }
    }
}

extension DiffScreen {
    @ViewBuilder fileprivate var placeholder: some View {
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
    fileprivate func refresh() async {
        if let onRefresh {
            await onRefresh()
        } else {
            await model.load(pullRequestID, headSHA: headSHA)
        }
    }

    private var isCommitMode: Bool { model.selectedCommit != nil }

    /// Everything that changes what a row shows for the same line.
    private var renderMode: String {
        "\(model.layout)|\(model.scope)|\(model.selectedCommit?.sha ?? "")"
    }

    /// A file's lines. A single commit's line numbers differ from the PR's: threads, AI highlights,
    /// comments and head context only apply to all changes.
    private func fileBody(_ file: FileDiff) -> some View {
        let commitMode = isCommitMode
        let comment: CommentRequest? =
            onStartComment == nil || commitMode
            ? nil
            : { side, line, extends in startComment(path: file.path, side: side, line: line, extends: extends) }
        let expand: ((Int, Int?) -> Void)? =
            commitMode ? nil : { hunk, count in Task { await model.expandContext(file, hunk: hunk, by: count) } }
        let hidden: [Int] = model.scope == .fullFile || commitMode ? [] : model.hiddenAbove(file)
        return DiffFileBodyView(
            path: file.path,
            hunks: model.hunks(for: file),
            layout: model.layout,
            accessory: { (location: CodeLocation) -> LineAccessory? in
                commitMode ? nil : lineAccessory(location)
            },
            highlight: { commitMode ? nil : model.highlight(path: file.path, newLine: $0) },
            onComment: comment,
            hiddenAbove: hidden,
            expand: expand,
            isExpanding: model.expandingPaths.contains(file.path)
        )
    }
}
