import DesignSystem
import SwiftUI

extension RiskLevel {
    var title: String {
        switch self {
        case .low: String(localized: "Low")
        case .medium: String(localized: "Medium")
        case .high: String(localized: "High")
        }
    }

    var tint: Color {
        switch self {
        case .low: .green
        case .medium: .orange
        case .high: .red
        }
    }
}

/// "Risk: Medium" capsule for the AI summary (pure).
struct RiskBadge: View {
    let level: RiskLevel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "gauge.with.dots.needle.33percent")
            Text("Risk: \(level.title)")
        }
        .aiFont(.caption2, weight: .bold)
        .foregroundStyle(level.tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(level.tint.opacity(0.15), in: Capsule())
        .help("How risky merging this pull request is, as rated by the AI review")
    }
}

/// "Impact high · Likelihood medium" below a finding's title (pure); empty for older reviews.
struct FindingRiskLine: View {
    let impact: RiskLevel?
    let likelihood: RiskLevel?

    var body: some View {
        if impact != nil || likelihood != nil {
            HStack(spacing: 10) {
                if let impact { part("Impact", impact) }
                if let likelihood { part("Likelihood", likelihood) }
            }
            .aiFont(.caption)
            .help("Impact: how bad it is if it happens. Likelihood: how likely it happens in practice.")
        }
    }

    private func part(_ name: LocalizedStringKey, _ level: RiskLevel) -> some View {
        HStack(spacing: 4) {
            Circle().fill(level.tint).frame(width: 6, height: 6)
            Text(name).foregroundStyle(.secondary)
            Text(level.title).foregroundStyle(level.tint).fontWeight(.medium)
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        ForEach(RiskLevel.allCases, id: \.self) { RiskBadge(level: $0) }
        FindingRiskLine(impact: .high, likelihood: .medium)
    }
    .padding()
}
