import FeatureDiff
import SwiftUI

// MARK: - Keyboard and command palette

extension RootScreen {
    var reviewActions: ReviewActions {
        ReviewActions(
            nextFile: { environment.diff.selectFile(offset: 1) },
            previousFile: { environment.diff.selectFile(offset: -1) },
            nextFinding: { jump(to: environment.aiReview.selectFinding(offset: 1, for: selection?.id)) },
            previousFinding: { jump(to: environment.aiReview.selectFinding(offset: -1, for: selection?.id)) },
            toggleViewed: {
                guard let path = environment.diff.selectedPath ?? environment.diff.orderedFiles.first?.path else {
                    return
                }
                Task { await environment.diff.toggleViewed(path) }
            },
            runAIReview: {
                guard let selection else { return }
                Task {
                    await environment.aiReview.run(
                        selection.id, title: selection.title, body: environment.pullRequest.detail?.body ?? "")
                }
            },
            openOnGitHub: { if let url = selection?.url { openURL(url) } },
            toggleInspector: { isInspectorPresented.toggle() },
            nextChange: { environment.diff.selectChange(offset: 1) },
            previousChange: { environment.diff.selectChange(offset: -1) },
            showPalette: { overlay = .palette },
            showShortcuts: { overlay = .shortcuts },
            find: { environment.diff.isSearchPresented = true },
            nextCommit: { Task { await environment.diff.selectCommit(offset: 1) } },
            previousCommit: { Task { await environment.diff.selectCommit(offset: -1) } }
        )
    }

    enum Overlay: String, Identifiable {
        case palette, shortcuts
        var id: String { rawValue }
    }

    /// Single-key review shortcuts (see `KeyboardShortcutsSheet`).
    func handleKey(_ key: String) -> Bool {
        let actions = reviewActions
        let keys: [String: () -> Void] = [
            "j": actions.nextFile, "k": actions.previousFile, "n": actions.nextChange, "p": actions.previousChange,
            ".": actions.nextFinding, ",": actions.previousFinding, "v": actions.toggleViewed,
            "i": actions.toggleInspector, "/": actions.find, "?": actions.showShortcuts,
        ]
        guard let action = keys[key] else { return false }
        action()
        return true
    }

    var paletteItems: [CommandPaletteSheet.Item] {
        let diff = environment.diff
        let files = diff.orderedFiles.map { file in
            CommandPaletteSheet.Item(
                id: "file:" + file.path, title: file.fileName, subtitle: file.directory, icon: "doc.text"
            ) { diff.selectedPath = file.path }
        }
        let actions = reviewActions
        var commands: [CommandPaletteSheet.Item] = [
            .init(id: "ai", title: String(localized: "Run AI review"), subtitle: "⌘⇧R", icon: "sparkles") {
                actions.runAIReview()
            },
            .init(id: "find", title: String(localized: "Find in diff"), subtitle: "⌘F", icon: "magnifyingglass") {
                actions.find()
            },
            .init(
                id: "inspector", title: String(localized: "Toggle AI inspector"), subtitle: "i", icon: "sidebar.right"
            ) {
                actions.toggleInspector()
            },
            .init(id: "submit", title: String(localized: "Submit review…"), subtitle: "", icon: "paperplane") {
                environment.review.isSubmitSheetPresented = true
            },
            .init(id: "github", title: String(localized: "Open on GitHub"), subtitle: "⌘⇧G", icon: "safari") {
                actions.openOnGitHub()
            },
            .init(id: "shortcuts", title: String(localized: "Keyboard shortcuts"), subtitle: "?", icon: "keyboard") {
                actions.showShortcuts()
            },
        ]
        if diff.progress?.lastReviewedSHA != nil {
            commands.append(
                .init(
                    id: "since", title: String(localized: "Show changes since my last review"), subtitle: "",
                    icon: "clock.arrow.circlepath"
                ) { Task { await diff.setScope(.sinceLastReview) } })
        }
        return commands + files
    }
}
