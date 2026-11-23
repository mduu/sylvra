import DesignSystem
import SwiftUI

/// One finding in the inspector list (pure).
struct FindingRowView: View {
    let finding: ReviewFinding
    let isSelected: Bool
    /// Which pull request, for the copied text.
    var pullRequest: String?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack(alignment: .firstTextBaseline, spacing: 8) {
                Circle().fill(finding.severity.color).frame(width: 8, height: 8)
                Text(finding.title).aiFont(.callout, weight: .semibold).fixedSize(horizontal: false, vertical: true)
                Spacer(minLength: 4)
                CopyButton("Copy for an agent") { AIReviewClipboard.finding(finding, pullRequest: pullRequest) }
            }
            HStack(spacing: 4) {
                Text(finding.location.description)
                Text(verbatim: "·")
                Text(finding.sources.map { $0.model.capitalized }.joined(separator: " + "))
                if !finding.isAnchored { Image(systemName: "mappin.slash").help("Not in the diff") }
            }
            .aiFont(.caption)
            .foregroundStyle(.secondary)
            .padding(.leading, 16)
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(
            isSelected ? AnyShapeStyle(AIAccent.cardBackground) : AnyShapeStyle(.quaternary.opacity(0.5)),
            in: RoundedRectangle(cornerRadius: 10)
        )
        .overlay {
            if isSelected { RoundedRectangle(cornerRadius: 10).strokeBorder(AIAccent.border, lineWidth: 1.2) }
        }
        .copyMenu { AIReviewClipboard.finding(finding, pullRequest: pullRequest) }
    }
}

/// Expanded finding: rationale, suggestion and actions (pure).
public struct FindingDetailView: View {
    let finding: ReviewFinding
    let actions: FindingActions
    /// Which pull request, for the copied text.
    let pullRequest: String?

    public init(finding: ReviewFinding, actions: FindingActions, pullRequest: String? = nil) {
        self.finding = finding
        self.actions = actions
        self.pullRequest = pullRequest
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            HStack(spacing: 8) {
                Text(finding.severity.rawValue.uppercased())
                    .aiFont(.caption2, weight: .bold)
                    .foregroundStyle(finding.severity.color)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 2)
                    .background(finding.severity.color.opacity(0.15), in: Capsule())
                Text(finding.title).aiFont(.callout, weight: .semibold)
                Spacer(minLength: 4)
                CopyButton("Copy for an agent") { AIReviewClipboard.finding(finding, pullRequest: pullRequest) }
            }
            FindingRiskLine(impact: finding.impact, likelihood: finding.likelihood)
            Text(finding.rationale).aiFont(.callout).fixedSize(horizontal: false, vertical: true).textSelection(
                .enabled)
            if let suggestion = finding.suggestion {
                Text(suggestion)
                    .aiFont(size: 11.5, design: .monospaced)
                    .padding(8)
                    .frame(maxWidth: .infinity, alignment: .leading)
                    .background(Color.green.opacity(0.12), in: RoundedRectangle(cornerRadius: 6))
            }
            HStack {
                if let comment = actions.turnIntoComment {
                    Button("Turn into comment", action: comment).buttonStyle(.borderedProminent)
                }
                if let open = actions.openInIDE { Button("Open in IDE", action: open) }
                Spacer()
                Button("Dismiss", action: actions.dismiss).buttonStyle(.borderless)
            }
            .controlSize(.small)
        }
        .padding(12)
        .background(AIAccent.cardBackground, in: RoundedRectangle(cornerRadius: 12))
        .overlay { RoundedRectangle(cornerRadius: 12).strokeBorder(AIAccent.border, lineWidth: 1) }
        .copyMenu { AIReviewClipboard.finding(finding, pullRequest: pullRequest) }
    }
}

/// Callbacks for a finding (provided by containers; optional ones are hidden when `nil`).
public struct FindingActions {
    public var turnIntoComment: (() -> Void)?
    public var askInChat: (() -> Void)?
    public var openInIDE: (() -> Void)?
    public var dismiss: () -> Void

    public init(
        turnIntoComment: (() -> Void)? = nil, askInChat: (() -> Void)? = nil, openInIDE: (() -> Void)? = nil,
        dismiss: @escaping () -> Void
    ) {
        self.turnIntoComment = turnIntoComment
        self.askInChat = askInChat
        self.openInIDE = openInIDE
        self.dismiss = dismiss
    }
}

/// Pattern verdict row (pure).
struct PatternRowView: View {
    let pattern: PatternFinding
    /// Its evidence is marked in the diff.
    var isSelected = false
    /// Which pull request, for the copied text.
    var pullRequest: String?
    /// Shows a piece of evidence in the diff; `nil` keeps the locations as plain text.
    var jump: ((CodeLocationText) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            HStack {
                Text(pattern.name).aiFont(.callout, weight: .medium)
                Spacer()
                Text(pattern.verdict.title)
                    .aiFont(.caption, weight: .semibold)
                    .foregroundStyle(pattern.verdict.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(pattern.verdict.color.opacity(0.14), in: Capsule())
                CopyButton("Copy for an agent") { AIReviewClipboard.pattern(pattern, pullRequest: pullRequest) }
            }
            if !pattern.rationale.isEmpty {
                Text(pattern.rationale).aiFont(.caption).foregroundStyle(.secondary).fixedSize(
                    horizontal: false, vertical: true)
            }
            if !pattern.evidence.isEmpty {
                FlowLocations(locations: pattern.evidence, jump: jump)
            }
        }
        .padding(.vertical, 6)
        .padding(.horizontal, 8)
        .background(
            isSelected ? AnyShapeStyle(AIAccent.cardBackground) : AnyShapeStyle(.clear), in: .rect(cornerRadius: 10)
        )
        .overlay {
            if isSelected { RoundedRectangle(cornerRadius: 10).strokeBorder(AIAccent.border, lineWidth: 1.2) }
        }
        .contentShape(Rectangle())
        // The whole row shows the first piece of evidence.
        .onTapGesture { if let first = pattern.evidence.first { jump?(first) } }
        .help(jump == nil || pattern.evidence.isEmpty ? "" : String(localized: "Show in the diff"))
        .copyMenu { AIReviewClipboard.pattern(pattern, pullRequest: pullRequest) }
    }
}

/// Evidence locations as links to the diff (pure).
private struct FlowLocations: View {
    let locations: [CodeLocationText]
    let jump: ((CodeLocationText) -> Void)?

    var body: some View {
        VStack(alignment: .leading, spacing: 2) {
            ForEach(locations, id: \.self) { location in
                if let jump {
                    Button {
                        jump(location)
                    } label: {
                        Label(location.description, systemImage: "arrow.right.circle")
                            .aiFont(.caption, design: .monospaced)
                    }
                    .buttonStyle(.link)
                    .help("Show \(location.path) in the diff")
                } else {
                    Text(location.description).aiFont(.caption, design: .monospaced).foregroundStyle(.tertiary)
                }
            }
        }
    }
}

/// Status of one agent job (pure).
/// Before the agents start: what the review is preparing (pure).
struct ReviewPreparationRowView: View {
    let step: String

    var body: some View {
        HStack(spacing: 8) {
            ProgressView().controlSize(.mini)
            Text(step).aiFont(.caption).lineLimit(1)
            Spacer()
        }
    }
}

#Preview("Preparing") {
    ReviewPreparationRowView(step: "Checking out the pull request…").padding().frame(width: 300)
}

struct AgentProgressRowView: View {
    let progress: ReviewEngine.Progress

    var body: some View {
        HStack(spacing: 8) {
            switch progress.state {
            case .queued: Image(systemName: "clock").foregroundStyle(.secondary)
            case .running: ProgressView().controlSize(.mini)
            case .done: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
            case .failed: Image(systemName: "exclamationmark.triangle.fill").foregroundStyle(.red)
            }
            Text(progress.title).aiFont(.caption).lineLimit(1)
            Spacer()
            Text(stateText).aiFont(.caption).foregroundStyle(.secondary)
        }
        .help(helpText)
    }

    private var stateText: String {
        switch progress.state {
        case .queued: String(localized: "queued")
        case .running: String(localized: "reviewing…")
        case .done: String(localized: "done")
        case .failed: String(localized: "failed")
        }
    }

    private var helpText: String {
        if case .failed(let message) = progress.state { return message }
        return progress.title
    }
}

extension FindingSeverity {
    var color: Color {
        switch self {
        case .critical: .red
        case .major: Color(red: 0.92, green: 0.35, blue: 0.43)
        case .minor: SylvraColor.accentGold
        case .nit: .secondary
        }
    }
}

extension PatternFinding.Verdict {
    var title: String {
        switch self {
        case .followed: String(localized: "followed")
        case .violated: String(localized: "violated")
        case .introduced: String(localized: "introduced")
        }
    }

    var color: Color {
        switch self {
        case .followed: .green
        case .violated: .red
        case .introduced: SylvraColor.brandPrimary
        }
    }
}
