import DesignSystem
import SwiftUI

/// Points about the pull request as a whole, above the line findings (pure): more compact, too much code,
/// too scattered.
struct OverallFindingsView: View {
    let points: [OverallFinding]

    var body: some View {
        VStack(alignment: .leading, spacing: 8) {
            Label("Whole pull request", systemImage: "square.stack.3d.up")
                .aiFont(.caption, weight: .semibold)
                .foregroundStyle(.secondary)
            ForEach(points) { point in
                VStack(alignment: .leading, spacing: 4) {
                    HStack(alignment: .firstTextBaseline, spacing: 6) {
                        Image(systemName: point.kind.symbol).foregroundStyle(AIAccent.border)
                        Text(point.title).aiFont(.callout, weight: .semibold)
                            .fixedSize(horizontal: false, vertical: true)
                    }
                    Text(point.kind.title)
                        .aiFont(.caption2, weight: .semibold)
                        .foregroundStyle(.secondary)
                    if !point.rationale.isEmpty {
                        Text(point.rationale).aiFont(.caption).foregroundStyle(.secondary)
                            .fixedSize(horizontal: false, vertical: true)
                            .textSelection(.enabled)
                    }
                }
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AIAccent.cardBackground, in: RoundedRectangle(cornerRadius: 10))
        .overlay { RoundedRectangle(cornerRadius: 10).strokeBorder(AIAccent.border.opacity(0.6), lineWidth: 1) }
    }
}

extension OverallFinding.Kind {
    var title: LocalizedStringKey {
        switch self {
        case .simpler: "Could be simpler"
        case .tooMuchCode: "Too much code"
        case .scattered: "Too scattered"
        case .other: "Whole change"
        }
    }

    var symbol: String {
        switch self {
        case .simpler: "arrow.down.right.and.arrow.up.left"
        case .tooMuchCode: "text.alignleft"
        case .scattered: "square.grid.3x3.topleft.filled"
        case .other: "sparkles"
        }
    }
}

#Preview {
    OverallFindingsView(points: [
        OverallFinding(
            kind: .scattered, title: "Export formats are defined in two places",
            rationale: "ExportFormat and CSVEncoder both list the formats."),
        OverallFinding(
            kind: .simpler, title: "The cache wrapper duplicates JSONCache",
            rationale: "InvoiceCache re-implements what JSONCache already does."),
    ])
    .padding()
    .frame(width: 340)
}
