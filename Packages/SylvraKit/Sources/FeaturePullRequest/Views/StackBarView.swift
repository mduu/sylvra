import DesignSystem
import SwiftUI
import SylvraCore

/// Where the pull request sits in its stack, with the layers below and above one click away, and what the
/// reviewer should know: the parent isn't merged yet, or the branch misses the parent's latest commits (pure).
struct StackBarView: View {
    let status: StackStatus
    let open: (PullRequestSummary) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack(spacing: 4) {
                layersMenu
                Spacer(minLength: 4)
                if let parent = status.parent {
                    neighbourButton(
                        parent, systemImage: "arrow.down",
                        help: String(localized: "Layer below: \(parent.summary.title)"))
                }
                if let child = status.child {
                    neighbourButton(
                        child, systemImage: "arrow.up", help: String(localized: "Layer above: \(child.summary.title)"))
                }
            }
            if let parent = status.parent { hint(for: parent) }
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 7)
        .background(SylvraColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(.separator))
    }

    /// All layers, top first like on GitHub; the trunk at the bottom.
    private var layersMenu: some View {
        Menu {
            ForEach(status.stack.entries.reversed()) { entry in
                Button {
                    open(entry.summary)
                } label: {
                    if entry.id == status.current {
                        Label(title(of: entry), systemImage: "checkmark")
                    } else {
                        Text(verbatim: title(of: entry))
                    }
                }
                .disabled(entry.id == status.current)
            }
            Divider()
            Text("Base: \(status.stack.trunk)")
        } label: {
            Label("Stack · \(status.position) of \(status.size)", systemImage: "square.stack.3d.up")
                .font(.caption.weight(.medium))
        }
        .menuStyle(.borderlessButton)
        .fixedSize()
        .help(
            status.stack.source == .gitHub
                ? String(localized: "Stacked pull request on GitHub")
                : String(localized: "Pull requests building on each other's branches"))
    }

    private func neighbourButton(_ entry: PullRequestStack.Entry, systemImage: String, help: String) -> some View {
        Button {
            open(entry.summary)
        } label: {
            Label {
                Text(verbatim: "#\(entry.summary.id.number)")
            } icon: {
                Image(systemName: systemImage)
            }
            .font(.caption.monospacedDigit())
        }
        .buttonStyle(.borderless)
        .help(help)
    }

    @ViewBuilder private func hint(for parent: PullRequestStack.Entry) -> some View {
        let number = "#\(parent.summary.id.number)"
        if status.needsRestack, let behind = status.commitsBehindParent {
            Label(
                "\(number) has \(behind) commit(s) this branch doesn't include yet: the diff doesn't show its latest state.",
                systemImage: "arrow.triangle.2.circlepath"
            )
            .font(.caption)
            .foregroundStyle(SylvraColor.accentGold)
            .fixedSize(horizontal: false, vertical: true)
        } else if status.isParentOpen {
            Label("Builds on \(number), which isn't merged yet.", systemImage: "arrow.turn.left.down")
                .font(.caption)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
        }
    }

    private func title(of entry: PullRequestStack.Entry) -> String {
        let state =
            switch entry.state {
            case .merged: String(localized: " (merged)")
            case .closed: String(localized: " (closed)")
            case .open: ""
            }
        return "#\(entry.summary.id.number) \(entry.summary.title)\(state)"
    }
}

#Preview("Stack bar") {
    VStack(spacing: 12) {
        StackBarView(status: StackBarView.fixture(behind: 0, parentState: .open), open: { _ in })
        StackBarView(status: StackBarView.fixture(behind: 3, parentState: .open), open: { _ in })
        StackBarView(status: StackBarView.fixture(behind: nil, parentState: .merged), open: { _ in })
    }
    .padding()
    .frame(width: 360)
}

extension StackBarView {
    static func fixture(behind: Int?, parentState: PullRequestDetail.State) -> StackStatus {
        let titles = ["Add invoice model", "Add invoice API", "Show invoices in the dashboard"]
        let entries = titles.enumerated().map { index, title in
            PullRequestStack.Entry(
                summary: PullRequestSummary(
                    id: PullRequestID(owner: "acme", repository: "billing", number: 1230 + index), title: title,
                    author: UserRef(login: "lkeller"), createdAt: .now, updatedAt: .now, additions: 10, deletions: 2,
                    headRefName: "invoices/\(index + 1)", baseRefName: index == 0 ? "main" : "invoices/\(index)"),
                state: index == 0 ? parentState : .open)
        }
        return StackStatus(
            stack: PullRequestStack(source: .gitHub, trunk: "main", entries: entries),
            current: entries[1].id, commitsBehindParent: behind)
    }
}
