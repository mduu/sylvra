import DesignSystem
import SwiftUI

/// The Claude subscription's limits as rings in the toolbar (container), outside in as listed in the details:
/// outer ring the 5-hour window, middle the week, inner Fable's week. A click shows the details with the reset
/// times.
public struct ClaudeUsageToolbarPanel: View {
    private let model: ClaudeUsageModel
    @State private var isShowingDetails = false

    public init(model: ClaudeUsageModel) {
        self.model = model
    }

    public var body: some View {
        Button {
            isShowingDetails.toggle()
        } label: {
            // Constant size: toolbar items that change width can loop AppKit's constraint pass.
            UsageRingsView(remaining: rings, lineWidth: 2.8, gap: 1.2)
                .frame(width: 26, height: 26)
                .contentShape(Rectangle())
        }
        .buttonStyle(.plain)
        .help(summary)
        .accessibilityLabel("Claude usage")
        .accessibilityValue(summary)
        .popover(isPresented: $isShowingDetails, arrowEdge: .bottom) {
            ClaudeUsageDetailsView(
                usage: model.usage, isRefreshing: model.isRefreshing, failure: model.failure,
                refresh: { Task { await model.refresh() } })
        }
        .onChange(of: isShowingDetails) { _, isShowing in
            if isShowing { Task { await model.refreshIfOlder(than: 120) } }
        }
        .task { await model.refreshIfOlder(than: 300) }
    }

    /// 5 hours, week and, once reported, Fable (outer to inner, the order of the details).
    private var rings: [Double?] {
        let now = Date.now
        guard let usage = model.usage else { return [nil, nil] }
        var rings = [usage.fiveHour?.remaining(at: now), usage.week?.remaining(at: now)]
        if let fable = usage.fable { rings.append(fable.remaining(at: now)) }
        return rings
    }

    private var summary: String {
        guard let usage = model.usage else { return String(localized: "Claude usage: not known yet") }
        return ClaudeUsageDetailsView.rows(of: usage)
            .map { "\($0.title): \(Int(($0.window.remaining() * 100).rounded())) % left" }
            .joined(separator: " · ")
    }
}

/// The popover: each limit with what is left and when it resets (pure).
struct ClaudeUsageDetailsView: View {
    let usage: ClaudeUsage?
    var isRefreshing = false
    var failure: String?
    let refresh: () -> Void
    var now = Date.now

    struct Row {
        let title: String
        let window: ClaudeUsage.Window
    }

    /// In the order of the toolbar rings, outside in.
    static func rows(of usage: ClaudeUsage) -> [Row] {
        [
            usage.fiveHour.map { Row(title: String(localized: "5-hour limit"), window: $0) },
            usage.week.map { Row(title: String(localized: "Weekly · all models"), window: $0) },
            usage.fable.map { Row(title: String(localized: "Weekly · Fable"), window: $0) },
        ].compactMap { $0 }
    }

    var body: some View {
        VStack(alignment: .leading, spacing: 12) {
            HStack(alignment: .firstTextBaseline) {
                Text("Claude subscription").font(.headline)
                Spacer()
                if let usage {
                    Text("Updated \(usage.updatedAt, format: .relative(presentation: .named))")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                }
                Button(action: refresh) {
                    if isRefreshing {
                        ProgressView().controlSize(.mini)
                    } else {
                        Image(systemName: "arrow.clockwise")
                    }
                }
                .buttonStyle(.borderless)
                .disabled(isRefreshing)
                .help("Ask Claude Code for the current limits (a tiny Haiku request)")
            }
            if let usage, !usage.isEmpty {
                let rows = Self.rows(of: usage)
                ForEach(Array(rows.enumerated()), id: \.element.title) { index, row in
                    rowView(row, ring: index, of: rows.count)
                }
                if let warning = warning(for: usage) {
                    Label(warning, systemImage: "exclamationmark.triangle.fill")
                        .font(.caption)
                        .foregroundStyle(.secondary)
                        .fixedSize(horizontal: false, vertical: true)
                }
            } else {
                Text(
                    failure ?? String(localized: "Not known yet: the limits come with every AI review and chat answer.")
                )
                .font(.callout)
                .foregroundStyle(.secondary)
                .fixedSize(horizontal: false, vertical: true)
            }
            Text("From Claude Code's own reports; work in other Claude sessions shows up with the next update.")
                .font(.caption2)
                .foregroundStyle(.tertiary)
                .fixedSize(horizontal: false, vertical: true)
        }
        .padding(14)
        .frame(width: 320)
    }

    /// The mini rings show where this limit sits in the toolbar: all tracks, only its own ring filled.
    private func rowView(_ row: Row, ring: Int, of count: Int) -> some View {
        let remaining = row.window.remaining(at: now)
        var rings = [Double?](repeating: nil, count: count)
        rings[ring] = remaining
        return VStack(alignment: .leading, spacing: 5) {
            HStack(spacing: 10) {
                UsageRingsView(remaining: rings, lineWidth: 3, gap: 1.2)
                    .frame(width: 28, height: 28)
                VStack(alignment: .leading, spacing: 1) {
                    Text(row.title).font(.callout.weight(.semibold))
                    Text(resetText(row.window)).font(.caption).foregroundStyle(.secondary)
                }
                Spacer()
                Text(verbatim: "\(Int((remaining * 100).rounded())) %")
                    .font(.title3.weight(.bold).monospacedDigit())
                    .foregroundStyle(UsageRingsView.color(for: remaining))
            }
            ProgressView(value: remaining)
                .progressViewStyle(.linear)
                .tint(UsageRingsView.color(for: remaining))
                .padding(.leading, 36)
        }
        .accessibilityElement(children: .combine)
    }

    private func resetText(_ window: ClaudeUsage.Window) -> String {
        guard let reset = window.resetsAt else { return String(localized: "Reset time unknown") }
        if reset <= now { return String(localized: "Reset — full again") }
        let time =
            Calendar.current.isDateInToday(reset)
            ? reset.formatted(date: .omitted, time: .shortened)
            : reset.formatted(.dateTime.weekday(.abbreviated).hour().minute())
        let left = reset.formatted(.relative(presentation: .numeric))
        return String(localized: "Resets \(time) · \(left)")
    }

    /// The tightest limit, when it runs low.
    private func warning(for usage: ClaudeUsage) -> String? {
        let tight = Self.rows(of: usage).min { $0.window.remaining(at: now) < $1.window.remaining(at: now) }
        guard let tight, ClaudeUsage.Level(remaining: tight.window.remaining(at: now)) != .plenty else { return nil }
        let reset = tight.window.resetsAt.map { $0.formatted(.dateTime.weekday(.abbreviated).hour().minute()) }
        if let reset {
            return String(localized: "\(tight.title) is running low: AI reviews may stop until \(reset).")
        }
        return String(localized: "\(tight.title) is running low: AI reviews may stop.")
    }
}

#Preview {
    let now = Date.now
    ClaudeUsageDetailsView(
        usage: ClaudeUsage(
            fiveHour: .init(utilization: 0.41, resetsAt: now.addingTimeInterval(6_000)),
            week: .init(utilization: 0.18, resetsAt: now.addingTimeInterval(300_000)),
            fable: .init(utilization: 0.83, resetsAt: now.addingTimeInterval(300_000))),
        refresh: {})
}
