import FeatureOpenInIDE
import SwiftUI

/// Sylvra → Show Worktrees in Finder / Clean Up Worktrees (see Settings → Worktrees for the list).
struct WorktreeCommands: Commands {
    let worktrees: WorktreesModel

    var body: some Commands {
        CommandGroup(after: .appSettings) {
            Button("Show Worktrees in Finder") { worktrees.showInFinder() }
            Button("Clean Up Worktrees") { Task { await worktrees.cleanUp() } }
        }
    }
}
