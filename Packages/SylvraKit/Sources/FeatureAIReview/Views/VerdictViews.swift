import DesignSystem
import SwiftUI

extension Mergeability {
    var title: String {
        switch self {
        case .excellent: String(localized: "Excellent")
        case .good: String(localized: "Good")
        case .acceptable: String(localized: "Acceptable")
        case .notMergeable: String(localized: "Not mergeable")
        }
    }

    var symbol: String {
        switch self {
        case .excellent: "star.fill"
        case .good: "checkmark.circle.fill"
        case .acceptable: "checkmark.circle"
        case .notMergeable: "xmark.octagon.fill"
        }
    }

    var tint: Color {
        switch self {
        case .excellent: .green
        case .good: .teal
        case .acceptable: .orange
        case .notMergeable: .red
        }
    }
}

extension SlopLevel {
    var title: String {
        switch self {
        case .none: String(localized: "None")
        case .some: String(localized: "Some")
        case .many: String(localized: "Many")
        }
    }

    var tint: Color {
        switch self {
        case .none: .green
        case .some: .orange
        case .many: .red
        }
    }

    /// How much careful human review is worth.
    var advice: String {
        switch self {
        case .none: String(localized: "Few signs of unreviewed code: worth a careful review.")
        case .some: String(localized: "Some signs of unreviewed code: look closely at the marked places.")
        case .many:
            String(
                localized:
                    "Many signs of unreviewed code: send the findings back to the author before reviewing in depth."
            )
        }
    }
}

/// "Good" capsule with the merge verdict for the AI summary (pure).
struct MergeabilityBadge: View {
    let level: Mergeability

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: level.symbol)
            Text(level.title)
        }
        .aiFont(.caption2, weight: .bold)
        .foregroundStyle(level.tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(level.tint.opacity(0.15), in: Capsule())
    }
}

/// "Slop: Some" capsule for the AI summary (pure).
struct SlopBadge: View {
    let level: SlopLevel

    var body: some View {
        HStack(spacing: 4) {
            Image(systemName: "scribble.variable")
            Text("Slop: \(level.title)")
        }
        .aiFont(.caption2, weight: .bold)
        .foregroundStyle(level.tint)
        .padding(.horizontal, 7)
        .padding(.vertical, 2)
        .background(level.tint.opacity(0.15), in: Capsule())
    }
}

/// The slop signs with their places, the review advice and, when worth it, copying the findings to send back
/// (pure).
struct SlopSignsView: View {
    let slop: SlopAssessment
    var openLocation: (CodeLocationText) -> Void = { _ in }
    /// Copies the findings to send back; `nil` hides the button.
    var copyFindings: (() -> String)?

    var body: some View {
        VStack(alignment: .leading, spacing: 4) {
            Text(slop.level.advice).aiFont(.caption, weight: .semibold)
                .fixedSize(horizontal: false, vertical: true)
            ForEach(slop.signs, id: \.self) { sign in
                VStack(alignment: .leading, spacing: 1) {
                    Text(verbatim: "· \(sign.title)").aiFont(.caption, weight: .medium)
                    if !sign.rationale.isEmpty {
                        Text(sign.rationale).aiFont(.caption).padding(.leading, 8)
                    }
                    if !sign.evidence.isEmpty {
                        HStack(spacing: 6) {
                            ForEach(sign.evidence, id: \.self) { location in
                                Button(location.description) { openLocation(location) }
                                    .buttonStyle(.link)
                                    .aiFont(.caption2)
                            }
                        }
                        .padding(.leading, 8)
                    }
                }
                .fixedSize(horizontal: false, vertical: true)
            }
            if let copyFindings {
                Button {
                    Clipboard.copy(copyFindings())
                } label: {
                    Label("Copy findings to send back", systemImage: "arrowshape.turn.up.backward")
                }
                .buttonStyle(.link)
                .aiFont(.caption)
                .padding(.top, 2)
                .help("All findings as Markdown, for the author or their coding agent")
            }
        }
        .foregroundStyle(.secondary)
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 12) {
        HStack {
            ForEach(Mergeability.allCases, id: \.self) { MergeabilityBadge(level: $0) }
        }
        HStack {
            ForEach(SlopLevel.allCases, id: \.self) { SlopBadge(level: $0) }
        }
        SlopSignsView(
            slop: SlopAssessment(
                level: .many,
                signs: [
                    SlopSign(
                        title: "Comments restate the code", rationale: "Every line of the export has a comment.",
                        evidence: [CodeLocationText(path: "Sources/Export.swift", startLine: 12, endLine: 30)]),
                    SlopSign(title: "Tests assert nothing", rationale: "Mocks return what the test expects."),
                ]),
            copyFindings: { "" })
    }
    .padding()
    .frame(width: 380)
}
