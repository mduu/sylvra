import SwiftUI

/// The user's notes on a repository's monitoring, passed to the agent with every check (container: saves on
/// *Save*). For what AGENTS.md / CLAUDE.md don't say: service names, environment tags, dashboards.
struct MonitoringNotesSheet: View {
    let repository: String
    @State var notes: String
    let save: (String) -> Void
    @Environment(\.dismiss) private var dismiss

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            Text("Monitoring notes for \(repository)").font(.headline)
            Text(
                """
                Tell the AI check where to look: service names, environment tags, dashboards, the log search to \
                use. It reads the repository's AGENTS.md / CLAUDE.md too. It can only use tools that are set \
                up and allowed in your own Claude Code settings.
                """
            )
            .font(.callout)
            .foregroundStyle(.secondary)
            .fixedSize(horizontal: false, vertical: true)
            TextEditor(text: $notes)
                .font(.body.monospaced())
                .frame(minHeight: 140)
                .overlay(RoundedRectangle(cornerRadius: 6).stroke(.quaternary))
            Text(verbatim: "Datadog: service:billing-api, env:dev | env:test | env:prod. Errors: status:error.")
                .font(.caption)
                .foregroundStyle(.tertiary)
            HStack {
                Spacer()
                Button("Cancel", role: .cancel) { dismiss() }.keyboardShortcut(.cancelAction)
                Button("Save") {
                    save(notes)
                    dismiss()
                }
                .keyboardShortcut(.defaultAction)
            }
        }
        .padding(20)
        .frame(width: 480)
    }
}

#Preview {
    MonitoringNotesSheet(repository: "acme/billing", notes: "Datadog: service:billing-api") { _ in }
}
