import SwiftUI

/// Actions of the focused main window, exposed to the menu bar (see specs/ux.md §14).
struct ReviewActions {
    var nextFile: () -> Void
    var previousFile: () -> Void
    var nextFinding: () -> Void
    var previousFinding: () -> Void
    var toggleViewed: () -> Void
    var runAIReview: () -> Void
    var openOnGitHub: () -> Void
    var toggleInspector: () -> Void
    var toggleInbox: () -> Void = {}
    var nextChange: () -> Void = {}
    var previousChange: () -> Void = {}
    var showPalette: () -> Void = {}
    var showShortcuts: () -> Void = {}
    var find: () -> Void = {}
    var nextCommit: () -> Void = {}
    var previousCommit: () -> Void = {}
}

extension FocusedValues {
    @Entry var reviewActions: ReviewActions?
}

/// The "Review" menu with the keyboard shortcuts of the review workflow, and their overview in the Help menu.
struct ReviewCommands: Commands {
    @FocusedValue(\.reviewActions) private var actions

    var body: some Commands {
        CommandMenu("Review") {
            Button("Command Palette…") { actions?.showPalette() }.keyboardShortcut("k", modifiers: .command)
            Button("Find in Diff…") { actions?.find() }.keyboardShortcut("f", modifiers: .command)
            Divider()
            Button("Next File") { actions?.nextFile() }.keyboardShortcut("]", modifiers: .command)
            Button("Previous File") { actions?.previousFile() }.keyboardShortcut("[", modifiers: .command)
            Button("Next Change  (n)") { actions?.nextChange() }
            Button("Previous Change  (p)") { actions?.previousChange() }
            Button("Next Commit") { actions?.nextCommit() }.keyboardShortcut("]", modifiers: .option)
            Button("Previous Commit") { actions?.previousCommit() }.keyboardShortcut("[", modifiers: .option)
            Divider()
            Button("Next AI Finding") { actions?.nextFinding() }.keyboardShortcut(
                .downArrow, modifiers: [.command, .option])
            Button("Previous AI Finding") { actions?.previousFinding() }.keyboardShortcut(
                .upArrow, modifiers: [.command, .option])
            Divider()
            Button("Toggle Viewed") { actions?.toggleViewed() }.keyboardShortcut("v", modifiers: [.command, .option])
            Button("Run AI Review") { actions?.runAIReview() }.keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Open on GitHub") { actions?.openOnGitHub() }.keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Toggle Inbox") { actions?.toggleInbox() }.keyboardShortcut("0", modifiers: .command)
            Button("Toggle AI Inspector") { actions?.toggleInspector() }.keyboardShortcut(
                "i", modifiers: [.command, .option])
        }
        // An overview of the shortcuts is help, as in other Mac apps.
        CommandGroup(after: .help) {
            Button("Keyboard Shortcuts") { actions?.showShortcuts() }.keyboardShortcut("/", modifiers: .command)
        }
    }
}
