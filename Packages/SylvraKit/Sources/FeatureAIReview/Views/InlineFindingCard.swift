import DesignSystem
import SwiftUI

/// The selected AI finding inside the diff, below its lines (see specs/ux.md §7.3): a card with a gradient
/// frame (gold → lavender → indigo → teal), severity, rationale, the suggestion as a mini diff and actions (pure).
public struct InlineFindingCard: View {
    private let finding: ReviewFinding
    /// Current text of the finding's lines, shown as the removed side of the suggestion.
    private let originalLines: String
    private let ideName: String?
    private let actions: FindingActions

    public init(finding: ReviewFinding, originalLines: String, ideName: String? = nil, actions: FindingActions) {
        self.finding = finding
        self.originalLines = originalLines
        self.ideName = ideName
        self.actions = actions
    }

    public var body: some View {
        VStack(alignment: .leading, spacing: 10) {
            HStack(spacing: 8) {
                Text(finding.severity.rawValue.uppercased())
                    .aiFont(size: 10.5, weight: .bold)
                    .foregroundStyle(finding.severity.color)
                    .padding(.horizontal, 7)
                    .padding(.vertical, 2)
                    .background(finding.severity.color.opacity(0.16), in: Capsule())
                Text(finding.title).aiFont(size: 13.5, weight: .semibold)
                Spacer(minLength: 0)
                Image(systemName: "sparkles").foregroundStyle(AIAccent.border)
            }
            Text(meta).aiFont(.caption).foregroundStyle(.secondary)
            Text(finding.rationale)
                .aiFont(.callout)
                .lineSpacing(2)
                .fixedSize(horizontal: false, vertical: true)
                .textSelection(.enabled)
            if let suggestion = finding.suggestion {
                SuggestionMiniDiff(original: originalLines, suggestion: suggestion)
            }
            HStack(spacing: 8) {
                if let comment = actions.turnIntoComment {
                    Button("Turn into comment", action: comment)
                        .buttonStyle(.borderedProminent)
                        .tint(SylvraColor.brandPrimary)
                }
                if let ask = actions.askInChat { Button("Ask in chat", action: ask) }
                if let open = actions.openInIDE {
                    Button(ideName.map { "Open in \($0)" } ?? "Open in IDE", action: open)
                }
                Spacer(minLength: 0)
                Button("Dismiss", action: actions.dismiss).buttonStyle(.borderless).foregroundStyle(.secondary)
            }
            .controlSize(.small)
        }
        .padding(.horizontal, 16)
        .padding(.vertical, 14)
        .background(SylvraColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 11))
        .padding(1.2)
        .background(Self.frameGradient, in: RoundedRectangle(cornerRadius: 12))
        .shadow(color: AIAccent.colors[0].opacity(0.25), radius: 14, y: 4)
        .frame(maxWidth: 620, alignment: .leading)
    }

    private var meta: String {
        let models = finding.sources.map { $0.model.capitalized }.joined(separator: " + ")
        let lines =
            finding.startLine == finding.endLine
            ? String(localized: "line \(finding.startLine)")
            : String(localized: "lines \(finding.startLine)–\(finding.endLine)")
        let file = (finding.path as NSString).lastPathComponent
        return models.isEmpty ? "\(file) · \(lines)" : "\(file) · \(lines) · " + String(localized: "found by \(models)")
    }

    /// The design-preview frame: gold → lavender → indigo → teal.
    static let frameGradient = LinearGradient(
        stops: [
            .init(color: SylvraColor.accentGold, location: 0),
            .init(color: AIAccent.colors[0], location: 0.4),
            .init(color: AIAccent.colors[1], location: 0.7),
            .init(color: AIAccent.colors[2], location: 1),
        ],
        startPoint: .topLeading, endPoint: .bottomTrailing)
}

/// `− original` / `+ suggestion` lines in the diff colors (pure).
struct SuggestionMiniDiff: View {
    let original: String
    let suggestion: String

    var body: some View {
        VStack(alignment: .leading, spacing: 0) {
            ForEach(Array(lines(original).enumerated()), id: \.offset) { _, line in
                row("−", line, SylvraColor.diffRemoved)
            }
            ForEach(Array(lines(suggestion).enumerated()), id: \.offset) { _, line in
                row("+", line, SylvraColor.diffAdded)
            }
        }
        .aiFont(size: 11.5, design: .monospaced)
        .clipShape(RoundedRectangle(cornerRadius: 8))
        .overlay(RoundedRectangle(cornerRadius: 8).strokeBorder(SylvraColor.codeHairline))
    }

    private func lines(_ text: String) -> [String] {
        text.isEmpty ? [] : text.split(separator: "\n", omittingEmptySubsequences: false).map(String.init)
    }

    private func row(_ marker: String, _ text: String, _ tint: Color) -> some View {
        HStack(spacing: 8) {
            Text(marker).foregroundStyle(tint).fontWeight(.bold)
            Text(text).lineLimit(1)
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .padding(.vertical, 4)
        .background(tint.opacity(0.14))
    }
}
