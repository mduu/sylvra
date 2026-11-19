import DesignSystem
import SwiftUI

/// Quick filter chips, author filter and the persistent filter menu above the pull request list (pure).
struct InboxFilterBar: View {
    let filter: PullRequestFilter
    let authors: [String]
    let hiddenCount: Int
    var toggle: (QuickFilter) -> Void = { _ in }
    var showOnlyAuthor: (String?) -> Void = { _ in }
    var clear: () -> Void = {}
    var updatePreferences: ((inout InboxFilterPreferences) -> Void) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            ChipFlowLayout(spacing: 6) {
                preferencesMenu
                authorMenu
                ForEach(QuickFilter.allCases) { quickFilter in
                    let isOn = filter.quickFilters.contains(quickFilter)
                    Button {
                        toggle(quickFilter)
                    } label: {
                        Label(quickFilter.title, systemImage: quickFilter.systemImage)
                    }
                    .buttonStyle(ChipStyle(isOn: isOn))
                }
            }
            .padding(.horizontal, 10)
            if hiddenCount > 0 || filter.hasTemporaryFilters {
                HStack(spacing: 4) {
                    if hiddenCount > 0 {
                        Text("\(hiddenCount) hidden by filters")
                    }
                    Spacer()
                    if filter.hasTemporaryFilters {
                        Button("Clear", action: clear).buttonStyle(.link)
                    }
                }
                .font(.caption)
                .foregroundStyle(.secondary)
                .padding(.horizontal, 12)
            }
        }
        .padding(.vertical, 6)
        .frame(maxWidth: .infinity, alignment: .leading)
        // Solid sidebar color like the search field above it: a material turned grey (or bluish from the desktop
        // picture) next to the lavender list.
        .background(SylvraColor.surfaceSidebar.ignoresSafeArea(edges: .horizontal))
        .overlay(alignment: .bottom) {
            Rectangle().fill(SylvraColor.codeHairline).frame(height: 1)
        }
    }

    private var preferencesMenu: some View {
        Menu {
            Toggle(
                "Hide bots",
                isOn: Binding(
                    get: { filter.preferences.hidesBots },
                    set: { value in updatePreferences { $0.hidesBots = value } }))
            Toggle(
                "Hide drafts by others",
                isOn: Binding(
                    get: { filter.preferences.hidesOthersDrafts },
                    set: { value in updatePreferences { $0.hidesOthersDrafts = value } }))
            if !filter.preferences.hiddenAuthors.isEmpty {
                Section("Hidden authors — click to show again") {
                    ForEach(filter.preferences.hiddenAuthors, id: \.self) { login in
                        Button(login, systemImage: "eye.slash") { updatePreferences { $0.showAuthor(login) } }
                    }
                }
            }
        } label: {
            Label(
                filter.preferences.activeCount > 0 ? "Filters (\(filter.preferences.activeCount))" : "Filters",
                systemImage: "line.3.horizontal.decrease")
        }
        .menuIndicator(.hidden)
        .buttonStyle(ChipStyle(isOn: filter.preferences.activeCount > 0))
        .fixedSize()
        .help("Hide bots, drafts of others and specific authors")
    }

    private var authorMenu: some View {
        Menu {
            if filter.author != nil {
                Button("All authors") { showOnlyAuthor(nil) }
                Divider()
            }
            ForEach(authors, id: \.self) { login in
                Button(login) { showOnlyAuthor(login) }
            }
        } label: {
            Label(filter.author ?? String(localized: "Author"), systemImage: "person")
        }
        .menuIndicator(.hidden)
        .buttonStyle(ChipStyle(isOn: filter.author != nil))
        .fixedSize()
    }
}

/// Lays chips out in rows, wrapping when the sidebar is narrow.
struct ChipFlowLayout: Layout {
    var spacing: CGFloat = 6

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        // Without a proposed width (ideal size), report the widest chip, not all chips in one row:
        // the sidebar's width must not depend on how many chips there are.
        let widest = subviews.map { $0.sizeThatFits(.unspecified).width }.max() ?? 0
        let rows = arrange(width: proposal.width ?? widest, subviews: subviews)
        let width = rows.map { $0.width }.max() ?? 0
        let height = rows.map(\.height).reduce(0, +) + spacing * CGFloat(max(rows.count - 1, 0))
        return CGSize(width: proposal.width ?? max(width, widest), height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for row in arrange(width: bounds.width, subviews: subviews) {
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

    private func arrange(width: CGFloat, subviews: Subviews) -> [Row] {
        var rows: [Row] = [Row()]
        for index in subviews.indices {
            let size = subviews[index].sizeThatFits(.unspecified)
            let needed =
                rows[rows.count - 1].indices.isEmpty ? size.width : rows[rows.count - 1].width + spacing + size.width
            if needed > width, !rows[rows.count - 1].indices.isEmpty {
                rows.append(Row())
            }
            var row = rows[rows.count - 1]
            row.width = row.indices.isEmpty ? size.width : row.width + spacing + size.width
            row.height = max(row.height, size.height)
            row.indices.append(index)
            rows[rows.count - 1] = row
        }
        return rows
    }
}

/// Capsule chip, tinted when on.
struct ChipStyle: ButtonStyle {
    let isOn: Bool

    func makeBody(configuration: Configuration) -> some View {
        configuration.label
            .labelStyle(.titleAndIcon)
            .font(.caption.weight(isOn ? .semibold : .regular))
            .padding(.horizontal, 8)
            .padding(.vertical, 4)
            .foregroundStyle(isOn ? AnyShapeStyle(SylvraColor.brandPrimary) : AnyShapeStyle(.secondary))
            .background(
                isOn ? AnyShapeStyle(SylvraColor.brandTint) : AnyShapeStyle(.quaternary.opacity(0.5)),
                in: Capsule()
            )
            .opacity(configuration.isPressed ? 0.7 : 1)
            .contentShape(Capsule())
    }
}

#Preview {
    InboxFilterBar(
        filter: PullRequestFilter(
            preferences: InboxFilterPreferences(hidesBots: true, hiddenAuthors: ["dg-renovate"]),
            quickFilters: [.needsReview]),
        authors: ["lkeller", "dg-renovate"], hiddenCount: 3
    )
    .frame(width: 320)
}
