import DesignSystem
import SwiftUI

/// What the AI check's card needs from the screen (closures out).
struct AICheckCardActions {
    /// Shows a stage's AI check in the details, optionally one of its checks.
    var select: (DeliveryStage, String?) -> Void
    /// Starts the check of a stage (`nil`: no agent).
    var verify: ((DeliveryStage) -> Void)?
    var stop: (DeliveryStage) -> Void
    /// Checks every stage that can be checked again.
    var verifyAll: (() -> Void)?
    /// Allows the tools Claude Code blocked (confirmed by the screen); `nil`: none blocked.
    var allowBlockedTools: (() -> Void)?
}

/// The AI check at the end of the graph as a verdict, not as workflow boxes (pure): the overall result in a
/// sentence, then one row per checked or checkable stage with its verdict and its checks as chips. AI content:
/// the AI accent.
struct AICheckCardView: View {
    let columns: [AICheckColumn]
    /// The stage whose AI check the details show (`nil`: none) and the check selected there.
    var selectedStageID: String?
    var selectedCheck: String?
    /// Blocked tools still not allowed, in short form.
    var blockedTools: [String] = []
    let actions: AICheckCardActions

    static let headerHeight: CGFloat = 110

    /// The height the card wants for its result sentence, rows and checks (the graph grows to fit it, up to its
    /// share of the screen).
    static func height(columns: [AICheckColumn]) -> CGFloat {
        // About 48 characters of the title font fit on a line of the card.
        let summary = columns.last { $0.result != nil }?.result?.summary.count ?? 60
        let headline = CGFloat(max(1, Int((Double(summary) / 48).rounded(.up)))) * 26
        return headerHeight + headline
            + columns.map { 60 + CGFloat($0.result?.checks.count ?? 0) * 30 }.reduce(0, +)
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            header
            Text(headline)
                .aiFont(.title3, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if !blockedTools.isEmpty { blockedLine }
            ScrollView {
                VStack(spacing: 8) {
                    ForEach(columns) { column in
                        AICheckRowView(
                            column: column, isSelected: column.stage.id == selectedStageID,
                            selectedCheck: column.stage.id == selectedStageID ? selectedCheck : nil, actions: actions)
                    }
                }
            }
            .scrollIndicators(.never)
        }
        .padding(16)
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .topLeading)
        .background(AIAccent.lineGradient(opacity: 0.14), in: RoundedRectangle(cornerRadius: 18, style: .continuous))
        .background(
            SylvraColor.surfaceElevated.opacity(0.6), in: RoundedRectangle(cornerRadius: 18, style: .continuous)
        )
        .overlay(
            RoundedRectangle(cornerRadius: 18, style: .continuous)
                .strokeBorder(AIAccent.border.opacity(selectedStageID == nil ? 0.5 : 0.9), lineWidth: 1.5)
        )
        .shadow(color: .black.opacity(0.15), radius: 8, y: 3)
    }

    private var header: some View {
        HStack(spacing: 8) {
            Label("AI check", systemImage: "sparkles")
                .font(.caption.weight(.heavy))
                .textCase(.uppercase)
                .foregroundStyle(AIAccent.border)
            if let latest = columns.compactMap(\.result?.checkedAt).max() {
                Text("\(latest.formatted(date: .omitted, time: .shortened)) · reads only")
                    .font(.caption).foregroundStyle(.secondary)
            }
            Spacer(minLength: 4)
            if let verifyAll = actions.verifyAll, columns.contains(where: { $0.isCheckable && !$0.isRunning }) {
                Button(columns.contains { $0.result != nil } ? "Check All Again" : "Check All", action: verifyAll)
                    .buttonStyle(.link)
                    .font(.caption)
            }
        }
    }

    /// The result in one sentence: the last checked stage's summary (production last), or what is going on.
    private var headline: String {
        if let running = columns.first(where: \.isRunning) {
            return String(localized: "Checking \(running.stage.name) in logs and monitoring…")
        }
        if let latest = columns.last(where: { $0.result != nil })?.result { return latest.summary }
        return String(
            localized:
                "Not checked yet. The AI check looks in logs and monitoring whether each stage deployed and what the change does there."
        )
    }

    private var blockedLine: some View {
        HStack(alignment: .firstTextBaseline, spacing: 6) {
            Image(systemName: "lock.fill").foregroundStyle(SylvraColor.statusWarning)
            Text("Claude Code blocked \(blockedTools.joined(separator: ", "))")
                .foregroundStyle(.secondary)
                .lineLimit(2)
                .fixedSize(horizontal: false, vertical: true)
            if let allow = actions.allowBlockedTools {
                Button("Allow…", action: allow)
                    .buttonStyle(.link)
                    .foregroundStyle(SylvraColor.statusWarning)
            }
        }
        .font(.caption)
    }
}

/// One stage in the card (pure): its verdict, how many checks came out how, the checks as chips — or the way to
/// start, stop or retry its check.
private struct AICheckRowView: View {
    let column: AICheckColumn
    let isSelected: Bool
    let selectedCheck: String?
    let actions: AICheckCardActions

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                badge
                Text(column.stage.name).font(.callout.weight(.semibold))
                Text(status).font(.callout.weight(.medium)).foregroundStyle(statusColor)
                Spacer(minLength: 4)
                trailing
            }
            if let checks = column.result?.checks, !checks.isEmpty, !column.isRunning {
                FlowChips(checks: checks, selected: selectedCheck) { title in actions.select(column.stage, title) }
            } else if let error = column.error {
                Text(error).font(.caption).foregroundStyle(SylvraColor.statusCritical).lineLimit(2)
            }
        }
        .padding(.horizontal, 12)
        .padding(.vertical, 10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            Color.black.opacity(isSelected ? 0.32 : 0.2), in: RoundedRectangle(cornerRadius: 12, style: .continuous)
        )
        .overlay {
            if isSelected {
                RoundedRectangle(cornerRadius: 12, style: .continuous).strokeBorder(
                    SylvraColor.brandPrimary, lineWidth: 1.5)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 12, style: .continuous))
        .onTapGesture { actions.select(column.stage, nil) }
        .accessibilityElement(children: .contain)
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    @ViewBuilder private var badge: some View {
        if column.isRunning {
            StateBadge(symbol: "sparkles", tint: SylvraColor.brandPrimary, isSpinning: true)
        } else if let result = column.result {
            StateBadge(
                symbol: result.verdict.badgeSymbol, tint: result.verdict.tint, isHollow: result.verdict == .unchecked)
        } else {
            StateBadge(symbol: "sparkles", tint: SylvraColor.brandPrimary, isHollow: true)
        }
    }

    private var status: String {
        if column.isRunning { return String(localized: "checking…") }
        if column.error != nil { return String(localized: "check failed") }
        return column.result?.verdict.title ?? String(localized: "not checked yet")
    }

    private var statusColor: Color {
        if column.error != nil { return SylvraColor.statusCritical }
        return column.result?.verdict.tint ?? .secondary
    }

    @ViewBuilder private var trailing: some View {
        if column.isRunning {
            Button("Stop") { actions.stop(column.stage) }.buttonStyle(.link).font(.caption)
        } else if column.result == nil || column.error != nil, column.isCheckable, let verify = actions.verify {
            Button(column.error == nil ? "Check with AI" : "Retry") { verify(column.stage) }
                .buttonStyle(.link).font(.caption)
        } else if let checks = column.result?.checks, !checks.isEmpty {
            let done = checks.count { $0.outcome != .unchecked }
            let open = checks.count - done
            Text(open > 0 ? "\(done) checked · \(open) open" : "\(done) checked")
                .font(.caption).foregroundStyle(.secondary)
            Image(systemName: "chevron.right").font(.caption2.weight(.bold)).foregroundStyle(.secondary)
        }
    }
}

/// The checks of a stage as chips that wrap (pure): a filled dot when checked, a ring when open, red on a
/// problem.
private struct FlowChips: View {
    let checks: [StageVerification.Check]
    let selected: String?
    let select: (String) -> Void

    var body: some View {
        ChipFlow(spacing: 6) {
            ForEach(checks) { check in
                Button {
                    select(check.title)
                } label: {
                    HStack(spacing: 5) {
                        Image(systemName: check.outcome == .unchecked ? "circle" : "circle.fill")
                            .font(.system(size: 6, weight: .bold))
                        Text(check.title).lineLimit(2).fixedSize(horizontal: false, vertical: true)
                    }
                    .font(.caption)
                    .foregroundStyle(chipColor(check))
                    .padding(.horizontal, 9)
                    .padding(.vertical, 3)
                    .background(chipColor(check).opacity(0.14), in: Capsule())
                    .overlay {
                        if check.title == selected { Capsule().strokeBorder(SylvraColor.brandPrimary, lineWidth: 1.2) }
                    }
                }
                .buttonStyle(.plain)
                .help("\(check.title)\n\(check.finding)")
            }
        }
    }

    private func chipColor(_ check: StageVerification.Check) -> Color {
        switch check.outcome {
        case .ok: .green
        case .problem: SylvraColor.statusCritical
        case .unchecked: .secondary
        }
    }
}

/// Lays chips out in lines, wrapping when a line is full.
private struct ChipFlow: Layout {
    var spacing: CGFloat

    func sizeThatFits(proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) -> CGSize {
        let width = proposal.width ?? .infinity
        let lines = arrange(subviews, width: width)
        let height = lines.map(\.height).reduce(0, +) + CGFloat(max(0, lines.count - 1)) * spacing
        return CGSize(width: proposal.width ?? lines.map(\.width).max() ?? 0, height: height)
    }

    func placeSubviews(in bounds: CGRect, proposal: ProposedViewSize, subviews: Subviews, cache: inout ()) {
        var y = bounds.minY
        for line in arrange(subviews, width: bounds.width) {
            var x = bounds.minX
            for index in line.indices {
                let size = Self.size(of: subviews[index], in: bounds.width)
                subviews[index].place(at: CGPoint(x: x, y: y), proposal: ProposedViewSize(size))
                x += size.width + spacing
            }
            y += line.height + spacing
        }
    }

    /// A chip as wide as its text, at most the whole line (a longer title wraps).
    private static func size(of subview: LayoutSubview, in width: CGFloat) -> CGSize {
        let ideal = subview.sizeThatFits(.unspecified)
        guard width.isFinite, ideal.width > width else { return ideal }
        return subview.sizeThatFits(ProposedViewSize(width: width, height: nil))
    }

    private struct Line {
        var indices: [Int] = []
        var width: CGFloat = 0
        var height: CGFloat = 0
    }

    private func arrange(_ subviews: Subviews, width: CGFloat) -> [Line] {
        var lines: [Line] = [Line()]
        for index in subviews.indices {
            let size = Self.size(of: subviews[index], in: width)
            let needed =
                lines[lines.count - 1].indices.isEmpty
                ? size.width : lines[lines.count - 1].width + spacing + size.width
            if needed > width, !lines[lines.count - 1].indices.isEmpty {
                lines.append(Line())
            }
            var line = lines[lines.count - 1]
            line.width = line.indices.isEmpty ? size.width : line.width + spacing + size.width
            line.height = max(line.height, size.height)
            line.indices.append(index)
            lines[lines.count - 1] = line
        }
        return lines
    }
}

#Preview {
    let delivery = DemoDeliveryLoader.delivery(for: .init(owner: "acme", repository: "billing", number: 812))
    let dev = delivery.stages[1]
    let test = delivery.stages[2]
    AICheckCardView(
        columns: [
            AICheckColumn(
                stage: dev, result: DemoDeliveryVerifier.verification(for: dev), isRunning: false, error: nil,
                isCheckable: true),
            AICheckColumn(stage: test, result: nil, isRunning: false, error: nil, isCheckable: true),
        ],
        selectedStageID: dev.id, blockedTools: ["datadog · analyze_datadog_logs"],
        actions: AICheckCardActions(
            select: { _, _ in }, verify: { _ in }, stop: { _ in }, verifyAll: {}, allowBlockedTools: {})
    )
    .frame(width: 520, height: 520)
    .padding()
}
