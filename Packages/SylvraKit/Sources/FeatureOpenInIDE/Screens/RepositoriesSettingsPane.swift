import AppKit
import SwiftUI

/// Settings → Repositories: where Sylvra looks for the user's own clones (saved per Mac).
public struct RepositoriesSettingsPane: View {
    @Bindable private var model: WorktreesModel

    public init(model: WorktreesModel) {
        self.model = model
    }

    public var body: some View {
        Form {
            RepositoryFoldersView(
                folders: model.repositorySearch.folders, usesSpotlight: $model.repositorySearch.usesSpotlight,
                add: chooseFolder, suggest: model.suggestRepositoryFolders, remove: model.removeRepositoryFolder)
        }
        .formStyle(.grouped)
    }

    private func chooseFolder() {
        let panel = NSOpenPanel()
        panel.canChooseDirectories = true
        panel.canChooseFiles = false
        panel.allowsMultipleSelection = true
        panel.prompt = String(localized: "Add")
        panel.directoryURL = FileManager.default.homeDirectoryForCurrentUser
        guard panel.runModal() == .OK else { return }
        for url in panel.urls { model.addRepositoryFolder(url) }
    }
}
