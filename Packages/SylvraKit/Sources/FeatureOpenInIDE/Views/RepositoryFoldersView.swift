import DesignSystem
import SwiftUI

/// The folders Sylvra searches for the user's clones, and the Spotlight fallback (pure).
public struct RepositoryFoldersView: View {
    let folders: [String]
    @Binding var usesSpotlight: Bool
    let add: () -> Void
    let suggest: () -> Void
    let remove: (String) -> Void

    public init(
        folders: [String], usesSpotlight: Binding<Bool>, add: @escaping () -> Void, suggest: @escaping () -> Void,
        remove: @escaping (String) -> Void
    ) {
        self.folders = folders
        self._usesSpotlight = usesSpotlight
        self.add = add
        self.suggest = suggest
        self.remove = remove
    }

    public var body: some View {
        Section {
            if folders.isEmpty {
                Text("No folders yet.").foregroundStyle(.secondary)
            }
            ForEach(folders, id: \.self) { folder in
                HStack {
                    Label((folder as NSString).abbreviatingWithTildeInPath, systemImage: "folder")
                        .lineLimit(1)
                        .truncationMode(.middle)
                    Spacer()
                    Button("Remove", systemImage: "minus.circle") { remove(folder) }
                        .labelStyle(.iconOnly)
                        .buttonStyle(.borderless)
                        .help("Don't search this folder")
                }
            }
            HStack {
                Button("Add Folder…", action: add)
                Button("Add Typical Folders", action: suggest)
                    .help("Adds folders like ~/Dev, ~/dev, ~/Projects or ~/Code that exist on this Mac")
            }
            Toggle("Also search with Spotlight", isOn: $usesSpotlight)
        } header: {
            Text("Your Repositories")
        } footer: {
            Text(
                // swiftlint:disable:next line_length
                "Worktrees are attached to your existing clone, so no repository is cloned twice. Sylvra looks in these folders first (in this order, three levels deep), then with Spotlight in your home folder. Only without any clone does it keep its own. Saved on this Mac."
            )
            .font(.caption)
            .foregroundStyle(.secondary)
        }
    }
}

#Preview {
    @Previewable @State var spotlight = true
    Form {
        RepositoryFoldersView(
            folders: ["/Users/me/Dev", "/Users/me/Projects/clients"], usesSpotlight: $spotlight, add: {},
            suggest: {}, remove: { _ in })
    }
    .formStyle(.grouped)
    .frame(width: 520)
}
