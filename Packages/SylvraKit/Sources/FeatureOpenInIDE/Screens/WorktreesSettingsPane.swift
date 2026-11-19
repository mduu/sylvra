import DesignSystem
import SwiftUI

/// Settings → Worktrees: what Sylvra checked out, with cleanup and Finder actions.
public struct WorktreesSettingsPane: View {
    private let model: WorktreesModel
    @State private var pendingRemoval: WorktreesModel.Entry?

    public init(model: WorktreesModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            Section {
                if model.entries.isEmpty {
                    Text("No worktrees right now.").foregroundStyle(.secondary)
                }
                ForEach(model.entries) { entry in
                    WorktreeRowView(
                        entry: entry, reveal: { model.reveal(entry) },
                        remove: {
                            if entry.hasChanges {
                                pendingRemoval = entry
                            } else {
                                Task { await model.remove(entry) }
                            }
                        })
                }
            } header: {
                Text("Worktrees")
            } footer: {
                Text(
                    // swiftlint:disable:next line_length
                    "Sylvra checks pull requests out in its own worktrees, never in your working copy. Worktrees of merged or closed pull requests and worktrees unused for a week are removed automatically (every 15 minutes); worktrees in use or with changed files stay."
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            Section {
                HStack {
                    Button("Clean Up Now") { Task { await model.cleanUp() } }
                        .disabled(model.isWorking)
                    Button("Show in Finder") { model.showInFinder() }
                    Spacer()
                    if model.isWorking { ProgressView().controlSize(.small) }
                }
                if let message = model.message {
                    Text(message).font(.caption).foregroundStyle(.secondary)
                }
                if let last = model.lastCleanup {
                    Text("Last cleanup \(last.formatted(.relative(presentation: .named)))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
            }
        }
        .formStyle(.grouped)
        .task { await model.refresh() }
        .confirmationDialog(
            "Remove a worktree with changed files?", isPresented: removalBinding, presenting: pendingRemoval
        ) { entry in
            Button("Remove and Discard Changes", role: .destructive) {
                Task { await model.remove(entry, force: true) }
            }
        } message: { entry in
            Text("Files in the worktree of \(entry.record.repository) were changed. Removing it discards them.")
        }
    }

    private var removalBinding: Binding<Bool> {
        Binding(get: { pendingRemoval != nil }, set: { if !$0 { pendingRemoval = nil } })
    }
}
