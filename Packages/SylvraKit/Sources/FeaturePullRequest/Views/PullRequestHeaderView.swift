import DesignSystem
import SwiftUI
import SylvraCore

/// Title, author, refs and status chips (pure).
struct PullRequestHeaderView: View {
    let detail: PullRequestDetail
    var isRefreshing = false
    var lastUpdated: Date?
    var refresh: (() -> Void)?
    /// What the merge button offers (`nil`: no button).
    var mergeAction: MergeOptions.Action?
    var merge: (() -> Void)?
    /// Merges past the branch rules (`nil`: not possible).
    var bypassRules: (() -> Void)?
    /// Copies the pull request's link; `true`: with its title and a short description.
    var copyLink: ((_ withDescription: Bool) -> Void)?
    @State private var didCopy = false
    let openOnGitHub: () -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            Text(detail.summary.title)
                .font(.title3.weight(.semibold))
                .fixedSize(horizontal: false, vertical: true)
            HStack(spacing: 8) {
                AvatarView(detail.summary.author, size: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(detail.summary.author.displayName).font(.callout.weight(.medium))
                    Text(verbatim: "\(detail.summary.headRefName) → \(detail.summary.baseRefName)")
                        .font(.caption.monospaced())
                        .foregroundStyle(.secondary)
                        .lineLimit(1)
                        .truncationMode(.middle)
                }
                Spacer(minLength: 0)
                if let refresh {
                    Button(action: refresh) {
                        if isRefreshing {
                            ProgressView().controlSize(.mini)
                        } else {
                            Image(systemName: "arrow.clockwise")
                        }
                    }
                    .buttonStyle(.borderless)
                    .frame(width: 18, height: 18)
                    .disabled(isRefreshing)
                    .help(refreshHelp)
                    .accessibilityLabel("Refresh pull request")
                }
                if copyLink != nil { copyLinkMenu }
                Button(action: openOnGitHub) {
                    Image(systemName: "arrow.up.right.square")
                }
                .buttonStyle(.borderless)
                .help("Open on GitHub")
            }
            FlowChips {
                StatusChip(
                    detail.mergeStatus.title, systemImage: detail.mergeStatus.symbol, tint: detail.mergeStatus.tint)
                StatusChip(checksTitle, systemImage: "checklist", tint: checksTint)
                StatusChip(
                    "+\(detail.summary.additions) −\(detail.summary.deletions) · \(detail.changedFiles) files",
                    systemImage: "plusminus", tint: .secondary)
            }
            if (mergeAction != nil && merge != nil) || bypassRules != nil {
                HStack(spacing: 8) {
                    if let mergeAction, let merge { mergeButton(mergeAction, merge) }
                    if let bypassRules {
                        Button(action: bypassRules) { Label("Bypass Rules…", systemImage: "exclamationmark.shield") }
                            .controlSize(.small)
                            .help("Merge now although required reviews or checks are missing")
                    }
                }
            }
        }
    }

    /// A click copies the link; the menu also offers it with title and description (for a review request).
    private var copyLinkMenu: some View {
        Menu {
            Button("Copy Link", systemImage: "link") { copy(withDescription: false) }
            Button("Copy Link with Description", systemImage: "text.bubble") { copy(withDescription: true) }
        } label: {
            Image(systemName: didCopy ? "checkmark" : "link")
                .foregroundStyle(didCopy ? AnyShapeStyle(.green) : AnyShapeStyle(.secondary))
                .contentTransition(.symbolEffect(.replace))
        } primaryAction: {
            copy(withDescription: false)
        }
        .menuStyle(.borderlessButton)
        .menuIndicator(.hidden)
        .fixedSize()
        .help("Copy the pull request's link — hold for the link with title and description")
        .accessibilityLabel("Copy link")
    }

    private func copy(withDescription: Bool) {
        copyLink?(withDescription)
        withAnimation(.snappy) { didCopy = true }
        Task {
            try? await Task.sleep(for: .seconds(1.2))
            withAnimation(.snappy) { didCopy = false }
        }
    }

    /// Merging is one click away, then confirmed in a sheet.
    @ViewBuilder private func mergeButton(_ action: MergeOptions.Action, _ merge: @escaping () -> Void) -> some View {
        switch action {
        case .merge:
            Button(action: merge) { Label("Merge…", systemImage: "arrow.triangle.merge") }
                .buttonStyle(.borderedProminent)
                .controlSize(.small)
                .help("Merge this pull request on GitHub")
        case .enableAutoMerge:
            Button(action: merge) { Label("Auto-Merge…", systemImage: "arrow.triangle.merge") }
                .controlSize(.small)
                .help("Let GitHub merge once reviews and checks are through")
        case .bypassRules:
            EmptyView()
        case .disableAutoMerge:
            Button(action: merge) { Label("Auto-merge is on", systemImage: "checkmark.circle") }
                .controlSize(.small)
                .help("GitHub merges once reviews and checks are through. Click to switch it off.")
        }
    }

    private var refreshHelp: String {
        guard let lastUpdated else { return String(localized: "Reload the pull request from GitHub") }
        let age = lastUpdated.formatted(.relative(presentation: .named))
        return String(localized: "Reload the pull request from GitHub (updated \(age))")
    }

    private var checksTitle: String {
        let failing = detail.checks.filter { $0.state == .failure || $0.state == .error }.count
        if failing > 0 { return String(localized: "\(failing) failing") }
        if detail.checks.contains(where: { $0.state == .pending }) { return String(localized: "Checks running") }
        return detail.checks.isEmpty ? String(localized: "No checks") : String(localized: "Checks passed")
    }

    private var checksTint: Color {
        if detail.checks.contains(where: { $0.state == .failure || $0.state == .error }) { return .red }
        if detail.checks.contains(where: { $0.state == .pending }) { return SylvraColor.accentGold }
        return .green
    }
}

/// Small capsule with icon and text.
struct StatusChip: View {
    let title: String
    let systemImage: String
    let tint: Color

    init(_ title: String, systemImage: String, tint: Color) {
        self.title = title
        self.systemImage = systemImage
        self.tint = tint
    }

    var body: some View {
        Label(title, systemImage: systemImage)
            .font(.caption.weight(.medium))
            .foregroundStyle(tint)
            .padding(.horizontal, 8)
            .padding(.vertical, 3)
            .background(tint.opacity(0.12), in: Capsule())
    }
}

/// Wraps chips onto multiple lines.
struct FlowChips<Content: View>: View {
    @ViewBuilder let content: Content

    var body: some View {
        FlowLayout(spacing: 6) { content }
    }
}

/// A simple left-to-right flow layout.
struct FlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let rows = arrange(proposal: proposal, subviews: subviews)
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? rows.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(proposal: proposal, subviews: subviews) {
            var x = bounds.minX
            for index in row.indices {
                let size = subviews[index].sizeThatFits(.unspecified)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += row.height + spacing
        }
    }

    private struct Row {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(proposal: ProposedViewSize, subviews: Subviews) -> [Row] {
        let maxWidth = proposal.width ?? .infinity
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            if let last = rows.last, !last.indices.isEmpty, last.width + spacing + size.width > maxWidth {
                rows.append(Row())
            }
            var row = rows.removeLast()
            row.width += (row.indices.isEmpty ? 0 : spacing) + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows.append(row)
        }
        return rows
    }
}

extension MergeStatus {
    var title: String {
        switch kind {
        case .ready: String(localized: "Ready to merge")
        case .blocked: String(localized: "Merge blocked")
        case .conflicts: String(localized: "Conflicts")
        case .behind: String(localized: "Behind base")
        case .unstable: String(localized: "Checks unstable")
        case .draft: String(localized: "Draft")
        case .merged: String(localized: "Merged")
        case .closed: String(localized: "Closed")
        case .unknown: String(localized: "Merge state unknown")
        }
    }

    var symbol: String {
        switch kind {
        case .ready, .merged: "checkmark.circle"
        case .blocked, .unstable: "nosign"
        case .conflicts: "exclamationmark.triangle"
        case .behind: "arrow.down.circle"
        case .draft: "pencil.circle"
        case .closed: "xmark.circle"
        case .unknown: "questionmark.circle"
        }
    }

    var tint: Color {
        switch kind {
        case .ready: .green
        case .merged: SylvraColor.brandPrimary
        case .blocked, .conflicts, .unstable: .red
        case .behind, .draft: SylvraColor.accentGold
        case .closed, .unknown: .secondary
        }
    }
}
