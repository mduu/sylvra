import SwiftUI

/// Form to add or edit a custom tool (pure: edits the binding, reports save / cancel).
struct CustomToolEditorView: View {
    @Binding var tool: CustomTool
    let isNew: Bool
    let save: () -> Void
    let cancel: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            Form {
                TextField("Name", text: $tool.name, prompt: Text("Run tests"))
                Picker("Scope", selection: $tool.scope) {
                    ForEach(CustomTool.Scope.allCases) { Text($0.title).tag($0) }
                }
                TextField(
                    "Command", text: $tool.command, prompt: Text(verbatim: "swift test --filter {file}"),
                    axis: .vertical
                )
                .font(.body.monospaced())
                .lineLimit(2...5)
                Text(
                    "Runs in a terminal tab in the pull request checkout. Placeholders are replaced by shell-escaped values: "
                        + CommandTemplate.Placeholder.allCases.map(\.token).joined(separator: " ")
                )
                .font(.caption)
                .foregroundStyle(.secondary)
            }
            .formStyle(.grouped)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel, action: cancel)
                    .keyboardShortcut(.cancelAction)
                Button(isNew ? "Add" : "Save", action: save)
                    .keyboardShortcut(.defaultAction)
                    .disabled(!isValid)
            }
            .padding([.horizontal, .bottom], 20)
        }
        .frame(width: 460)
    }

    private var isValid: Bool {
        !tool.name.trimmingCharacters(in: .whitespaces).isEmpty
            && !tool.command.trimmingCharacters(in: .whitespaces).isEmpty
    }
}

#Preview {
    @Previewable @State var tool = CustomTool.examples[1]
    CustomToolEditorView(tool: $tool, isNew: false, save: {}, cancel: {})
}
