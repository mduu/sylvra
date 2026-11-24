import DesignSystem
import SwiftUI
import SylvraCore

/// A pull request on the reviewer's to-do list (pure, presentational): a checkbox to mark it done, the usual row,
/// and a grip to drag it up or down.
struct InboxTodoRow: View {
    let pullRequest: PullRequestSummary
    /// Checked: about to leave the list.
    var isDone = false
    /// Merged or closed since it was put on the list.
    var isClosed = false
    /// Drag and drop works (not while searching).
    var canReorder = true
    let markDone: () -> Void

    var body: some View {
        HStack(alignment: .top, spacing: 8) {
            Button(action: markDone) {
                Image(systemName: isDone ? "checkmark.circle.fill" : "circle")
                    .font(.title3)
                    .foregroundStyle(isDone ? AnyShapeStyle(SylvraColor.brandPrimary) : AnyShapeStyle(.tertiary))
                    .contentTransition(.symbolEffect(.replace))
                    .frame(width: 20, height: 26)
                    .contentShape(Rectangle())
            }
            .buttonStyle(.borderless)
            .help("Mark as done: removes it from your to-do list")
            .accessibilityLabel(isDone ? "Done" : "Mark as done")
            VStack(alignment: .leading, spacing: 3) {
                InboxRowView(pullRequest: pullRequest)
                if isClosed {
                    Label("Merged or closed", systemImage: "checkmark.seal")
                        .font(.caption2.weight(.medium))
                        .foregroundStyle(.secondary)
                        .padding(.leading, 36)
                }
            }
            .opacity(isDone ? 0.45 : 1)
            if canReorder {
                Image(systemName: "line.3.horizontal")
                    .font(.callout)
                    .foregroundStyle(.tertiary)
                    .frame(height: 26)
                    .help("Drag to reorder")
                    .accessibilityHidden(true)
            }
        }
    }
}

#Preview {
    let pullRequests = DemoInboxLoader.sections[.myTeams] ?? []
    List {
        Section("To-Do") {
            ForEach(Array(pullRequests.prefix(3).enumerated()), id: \.element.id) { index, pullRequest in
                InboxTodoRow(pullRequest: pullRequest, isDone: index == 1, isClosed: index == 2, markDone: {})
            }
        }
    }
    .frame(width: 320)
}
