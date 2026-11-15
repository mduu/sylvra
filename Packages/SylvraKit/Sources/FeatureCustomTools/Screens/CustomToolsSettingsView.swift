import SwiftUI

/// Custom tools editor: add, edit, reorder and delete tools (a `Form` section for the settings window).
public struct CustomToolsSettingsView: View {
    private let store: CustomToolStore
    @State private var draft: Draft?

    private struct Draft: Identifiable {
        var tool: CustomTool
        let isNew: Bool
        var id: UUID { tool.id }
    }

    public init(store: CustomToolStore) {
        self.store = store
    }

    public var body: some View {
        Section {
            ForEach(store.tools) { tool in
                CustomToolRow(
                    tool: tool, edit: { draft = Draft(tool: tool, isNew: false) }, delete: { store.delete(tool.id) })
            }
            .onMove { store.move(fromOffsets: $0, toOffset: $1) }
            Button("Add Tool…") {
                draft = Draft(tool: CustomTool(name: "", scope: .pullRequest, command: ""), isNew: true)
            }
        } header: {
            Text("Custom tools")
        } footer: {
            Text("Tools appear in the context menu of files and folders and in the terminal menu for the pull request.")
                .font(.caption)
                .foregroundStyle(.secondary)
        }
        .sheet(item: $draft) { current in
            CustomToolEditorView(
                tool: Binding(get: { draft?.tool ?? current.tool }, set: { draft?.tool = $0 }),
                isNew: current.isNew,
                save: {
                    if let tool = draft?.tool { store.save(tool) }
                    draft = nil
                },
                cancel: { draft = nil })
        }
    }
}

/// One tool in the settings list (pure).
struct CustomToolRow: View {
    let tool: CustomTool
    let edit: () -> Void
    let delete: () -> Void

    var body: some View {
        HStack {
            VStack(alignment: .leading, spacing: 2) {
                HStack(spacing: 6) {
                    Text(tool.name)
                    Text(tool.scope.title)
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .padding(.horizontal, 6)
                        .padding(.vertical, 1)
                        .background(.quaternary, in: Capsule())
                }
                Text(tool.command)
                    .font(.caption.monospaced())
                    .foregroundStyle(.secondary)
                    .lineLimit(1)
                    .truncationMode(.tail)
            }
            Spacer()
            Button("Edit", action: edit)
            Button(role: .destructive, action: delete) {
                Image(systemName: "trash")
            }
            .buttonStyle(.borderless)
            .help("Delete tool")
            .accessibilityLabel("Delete \(tool.name)")
        }
        .contextMenu {
            Button("Edit…", action: edit)
            Button("Delete", role: .destructive, action: delete)
        }
    }
}

#Preview {
    Form {
        ForEach(CustomTool.examples) { CustomToolRow(tool: $0, edit: {}, delete: {}) }
    }
    .formStyle(.grouped)
}
