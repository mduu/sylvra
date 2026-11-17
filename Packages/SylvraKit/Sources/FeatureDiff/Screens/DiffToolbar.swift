import SwiftUI
import SylvraCore

/// The diff's toolbar controls (container): which changes (scope, commit by commit) and how (side by side or
/// inline). The app places them on the leading side of the window toolbar, next to the pull request info.
public struct DiffToolbar: ToolbarContent {
    let model: DiffScreenModel

    public init(model: DiffScreenModel) {
        self.model = model
    }

    public var body: some ToolbarContent {
        // Icons keep the toolbar narrow: a toolbar wider than the window makes AppKit's constraint pass loop.
        ToolbarItemGroup(placement: .navigation) {
            DiffScopeMenu(
                scope: model.scope, canShowSinceReview: model.progress?.lastReviewedSHA != nil,
                setScope: { scope in Task { await model.setScope(scope) } })
            if !model.commits.isEmpty {
                commitMenu
            }
            DiffLayoutControl(layout: model.layout) { model.layout = $0 }
        }
    }

    private var isCommitMode: Bool { model.selectedCommit != nil }

    /// All changes or one commit at a time.
    private var commitMenu: some View {
        Menu {
            Button("All changes") { Task { await model.showCommit(nil) } }
            Divider()
            ForEach(Array(model.commits.enumerated()), id: \.element.id) { index, commit in
                Button {
                    Task { await model.showCommit(commit) }
                } label: {
                    if commit == model.selectedCommit {
                        Label("\(index + 1). \(commit.subject)", systemImage: "checkmark")
                    } else {
                        Text(verbatim: "\(index + 1). \(commit.subject)")
                    }
                }
            }
        } label: {
            Label(
                "Commits",
                systemImage: isCommitMode
                    ? "point.topleft.down.to.point.bottomright.curvepath.fill"
                    : "point.topleft.down.to.point.bottomright.curvepath")
        }
        .help("Review commit by commit (⌥] / ⌥[)")
    }
}
