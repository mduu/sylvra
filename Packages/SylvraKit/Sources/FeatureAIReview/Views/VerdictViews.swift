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

extension KnowledgeLevel {
    var title: String {
        switch self {
        case .notable: String(localized: "Notable")
        case .minor: String(localized: "Minor")
        case .routine: String(localized: "None")
        }
    }

    var symbol: String {
        switch self {
        case .notable: "lightbulb.fill"
        case .minor: "lightbulb"
        case .routine: "broom"
        }
    }

    var tint: Color {
        switch self {
        case .notable: SylvraColor.accentGold
        case .minor: .teal
        case .routine: .secondary
        }
    }

    /// What it means for the reader.
    var advice: String {
        switch self {
        case .notable: String(localized: "Worth remembering: domain knowledge or a fundamental technical change.")
        case .minor: String(localized: "A small detail of the domain or the technical foundation.")
        case .routine: String(localized: "Nothing to remember: no new domain knowledge, no fundamental change.")
        }
    }
}

/// "Worth knowing" capsule for the AI summary (pure).
struct KnowledgeBadge: View {
    let level: KnowledgeLevel

    var body: some View {
        VerdictChip(symbol: level.symbol, title: String(localized: "Knowledge: \(level.title)"), tint: level.tint)
    }
}

extension TakeawayKind {
    var title: String {
        switch self {
        case .domain: String(localized: "Domain")
        case .technical: String(localized: "Technical")
        }
    }

    var symbol: String {
        switch self {
        case .domain: "building.columns"
        case .technical: "gearshape.2"
        }
    }
}

/// "Domain" or "Technical" before a takeaway (pure).
struct TakeawayKindTag: View {
    let kind: TakeawayKind

    var body: some View {
        Label(kind.title, systemImage: kind.symbol)
            .labelStyle(.titleAndIcon)
            .aiFont(.caption2, weight: .semibold)
            .foregroundStyle(.secondary)
            .padding(.horizontal, 5)
            .padding(.vertical, 1)
            .background(Color.secondary.opacity(0.12), in: Capsule())
            .fixedSize()
    }
}

/// What to remember about the change, with a copy button for notes or a changelog (pure).
struct KnowledgeTakeawaysView: View {
    let knowledge: KnowledgeAssessment

    var body: some View {
        VStack(alignment: .leading, spacing: 3) {
            HStack(spacing: 6) {
                Label("What to remember", systemImage: knowledge.level.symbol)
                    .aiFont(.caption, weight: .semibold)
                    .foregroundStyle(knowledge.level.tint)
                CopyButton("Copy what to remember") {
                    knowledge.takeaways.map { "- \($0.line)" }.joined(separator: "\n")
                }
            }
            ForEach(knowledge.takeaways, id: \.self) { takeaway in
                HStack(alignment: .firstTextBaseline, spacing: 6) {
                    if let kind = takeaway.kind { TakeawayKindTag(kind: kind) } else { Text(verbatim: "·") }
                    Text(takeaway.text)
                        .aiFont(.caption)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                }
            }
        }
    }
}

/// One rating of the AI summary as a capsule as wide as it is given (pure): symbol and title, the title cut
/// only when there is really no room.
struct VerdictChip: View {
    let symbol: String
    let title: String
    let tint: Color

    var body: some View {
        HStack(spacing: 5) {
            Image(systemName: symbol)
            Text(title).lineLimit(1).truncationMode(.tail)
        }
        .aiFont(.caption2, weight: .bold)
        .foregroundStyle(tint)
        .padding(.horizontal, 8)
        .padding(.vertical, 3)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(tint.opacity(0.15), in: Capsule())
        .contentShape(Capsule())
    }
}

/// "Good" capsule with the merge verdict for the AI summary (pure).
struct MergeabilityBadge: View {
    let level: Mergeability

    var body: some View {
        VerdictChip(symbol: level.symbol, title: String(localized: "Overall: \(level.title)"), tint: level.tint)
    }
}

/// "Slop: Some" capsule for the AI summary (pure).
struct SlopBadge: View {
    let level: SlopLevel

    var body: some View {
        VerdictChip(symbol: "scribble.variable", title: String(localized: "Slop: \(level.title)"), tint: level.tint)
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
        HStack {
            ForEach(KnowledgeLevel.allCases, id: \.self) { KnowledgeBadge(level: $0) }
        }
        KnowledgeTakeawaysView(
            knowledge: KnowledgeAssessment(
                level: .notable,
                takeaways: [
                    Takeaway("Invoices now round VAT per invoice, not per line.", kind: .domain),
                    Takeaway("Exports run in a background queue instead of the request.", kind: .technical),
                ]))
    }
    .padding()
    .frame(width: 380)
}
