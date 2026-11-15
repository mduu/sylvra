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
}

extension FocusedValues {
    @Entry var reviewActions: ReviewActions?
}

/// The "Review" menu with the keyboard shortcuts of the review workflow.
struct ReviewCommands: Commands {
    @FocusedValue(\.reviewActions) private var actions

    var body: some Commands {
        CommandMenu("Review") {
            Button("Next File") { actions?.nextFile() }.keyboardShortcut("]", modifiers: .command)
            Button("Previous File") { actions?.previousFile() }.keyboardShortcut("[", modifiers: .command)
            Divider()
            Button("Next AI Finding") { actions?.nextFinding() }.keyboardShortcut(
                .downArrow, modifiers: [.command, .option])
            Button("Previous AI Finding") { actions?.previousFinding() }.keyboardShortcut(
                .upArrow, modifiers: [.command, .option])
            Divider()
            Button("Toggle Viewed") { actions?.toggleViewed() }.keyboardShortcut("v", modifiers: [.command, .option])
            Button("Run AI Review") { actions?.runAIReview() }.keyboardShortcut("r", modifiers: [.command, .shift])
            Button("Open on GitHub") { actions?.openOnGitHub() }.keyboardShortcut("g", modifiers: [.command, .shift])
            Button("Toggle AI Inspector") { actions?.toggleInspector() }.keyboardShortcut(
                "i", modifiers: [.command, .option])
        }
    }
}
