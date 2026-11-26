import DesignSystem
import SwiftUI
import SylvraCore

/// The AI review's summary and reading order (container), placed by the app above the PR tabs so it stays
/// visible while reviewing. Hidden until a review has a summary. Marked with the AI accent.
public struct AISummaryPanel: View {
    private let model: AIReviewModel
    private let pullRequestID: PullRequestID?
    private let openFile: (String) -> Void
    @AppStorage("aiSummaryExpanded") private var isExpanded = false
    @AppStorage("aiReadingOrderExpanded") private var showsReadingOrder = false

    public init(model: AIReviewModel, pullRequestID: PullRequestID?, openFile: @escaping (String) -> Void) {
        self.model = model
        self.pullRequestID = pullRequestID
        self.openFile = openFile
    }

    public var body: some View {
        if let id = pullRequestID, let result = model.results[id], !result.summary.isEmpty {
            AISummaryCardView(
                summary: result.summary, risk: result.risk, mergeability: result.mergeability, slop: result.slop,
                knowledge: result.knowledge,
                readingOrder: result.readingOrder, isExpanded: $isExpanded, showsReadingOrder: $showsReadingOrder,
                openFile: openFile, pullRequest: AIReviewClipboard.pullRequestLine(id),
                copyFindings: copyFindings(for: result, id: id))
        }
    }

    /// Sending the findings back is offered when the review advises against reviewing in depth first.
    private func copyFindings(for result: ReviewResult, id: PullRequestID) -> (() -> String)? {
        let worthSendingBack =
            result.slop.map { $0.level != .none } == true || result.mergeability?.level == .notMergeable
        let findings = model.visibleFindings(for: id)
        guard worthSendingBack, !findings.isEmpty || !result.overall.isEmpty else { return nil }
        return {
            AIReviewClipboard.findings(
                findings, overall: result.overall, pullRequest: AIReviewClipboard.pullRequestLine(id))
        }
    }
}

/// Summary text (collapsed to a few lines) and the reading order on demand (pure).
struct AISummaryCardView: View {
    let summary: String
    var risk: RiskAssessment?
    var mergeability: MergeabilityAssessment?
    var slop: SlopAssessment?
    var knowledge: KnowledgeAssessment?
    let readingOrder: [ReadingStep]
    @Binding var isExpanded: Bool
    @Binding var showsReadingOrder: Bool
    var openFile: (String) -> Void = { _ in }
    /// Which pull request, for the copied text.
    var pullRequest: String?
    /// Copies the findings to send back to the author; `nil` hides it.
    var copyFindings: (() -> String)?
    @State private var contentHeight: CGFloat = 60

    static let maxExpandedHeight: CGFloat = 220

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("AI summary", systemImage: "sparkles")
                    .aiFont(.caption, weight: .semibold)
                    .foregroundStyle(AIAccent.border)
                Spacer()
                CopyButton("Copy for an agent", text: copyText)
                Button(isExpanded ? "Less" : "More") { withAnimation(.snappy) { isExpanded.toggle() } }
                    .buttonStyle(.link)
                    .aiFont(.caption)
            }
            if risk != nil || mergeability != nil || slop != nil || knowledge != nil {
                badges
            }
            // Expanded content scrolls inside the card (at most `maxExpandedHeight`): the card sits in the PR
            // column's pinned area, which must stay small and must not depend on the text's length.
            ScrollView {
                VStack(alignment: .leading, spacing: 6) {
                    Text(summary)
                        .aiFont(.callout)
                        .lineLimit(isExpanded ? nil : 3)
                        .textSelection(.enabled)
                        .fixedSize(horizontal: false, vertical: true)
                    if isExpanded, let risk, !risk.reasons.isEmpty {
                        reasons(String(localized: "Why \(risk.level.title.lowercased()) risk"), risk.reasons)
                    }
                    if isExpanded, let mergeability, !mergeability.reasons.isEmpty {
                        reasons(
                            String(localized: "Why \(mergeability.level.title.lowercased())"), mergeability.reasons)
                    }
                    if isExpanded, let knowledge, !knowledge.takeaways.isEmpty {
                        KnowledgeTakeawaysView(knowledge: knowledge)
                    }
                    if isExpanded, let slop {
                        SlopSignsView(
                            slop: slop, openLocation: { openFile($0.path) }, copyFindings: copyFindings)
                    }
                    if !readingOrder.isEmpty {
                        DisclosureGroup(isExpanded: $showsReadingOrder) {
                            ReadingOrderView(steps: readingOrder) { openFile($0.path) }
                                .padding(.top, 4)
                        } label: {
                            Text("Reading order (\(readingOrder.count) files)").aiFont(.caption).foregroundStyle(
                                .secondary)
                        }
                    }
                }
                .frame(maxWidth: .infinity, alignment: .leading)
                .onGeometryChange(for: CGFloat.self) {
                    $0.size.height
                } action: {
                    contentHeight = $0
                }
            }
            .scrollBounceBehavior(.basedOnSize)
            .frame(height: min(max(contentHeight, 1), Self.maxExpandedHeight))
        }
        .padding(10)
        .background(AIAccent.lineGradient(opacity: 0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AIAccent.border.opacity(0.45)))
        .copyMenu(text: copyText)
    }

    /// Merge verdict, risk and slop; the reasons in the tooltips (and below when expanded).
    private var badges: some View {
        HStack(spacing: 6) {
            if let mergeability {
                MergeabilityBadge(level: mergeability.level)
                    .help(tooltip("Whether it can be merged as it is", mergeability.reasons))
            }
            if let risk {
                RiskBadge(level: risk.level)
                    .help(tooltip("How risky merging this pull request is", risk.reasons))
            }
            if let slop {
                SlopBadge(level: slop.level)
                    .help(tooltip(slop.level.advice, slop.signs.map(\.title)))
            }
            if let knowledge {
                KnowledgeBadge(level: knowledge.level)
                    .help(tooltip(knowledge.level.advice, knowledge.takeaways))
            }
        }
    }

    private func tooltip(_ title: String, _ lines: [String]) -> String {
        ([title] + lines.map { "· \($0)" }).joined(separator: "\n")
    }

    private func reasons(_ title: String, _ reasons: [String]) -> some View {
        VStack(alignment: .leading, spacing: 2) {
            Text(title).aiFont(.caption, weight: .semibold)
            ForEach(reasons, id: \.self) { reason in
                Text(verbatim: "· \(reason)").aiFont(.caption).fixedSize(horizontal: false, vertical: true)
            }
        }
        .foregroundStyle(.secondary)
    }

    private func copyText() -> String {
        AIReviewClipboard.summary(
            summary, risk: risk, mergeability: mergeability, slop: slop, knowledge: knowledge,
            readingOrder: readingOrder,
            pullRequest: pullRequest)
    }
}

#Preview {
    @Previewable @State var isExpanded = false
    @Previewable @State var showsOrder = false
    AISummaryCardView(
        summary: "Adds CSV export next to JSON and changes how invoice totals are rounded (per line instead of "
            + "once). The rounding change affects every invoice total; the export is additive.",
        risk: RiskAssessment(level: .medium, reasons: ["Invoice totals change for existing customers"]),
        mergeability: MergeabilityAssessment(level: .acceptable, reasons: ["Rounding change lacks tests"]),
        slop: SlopAssessment(
            level: .some,
            signs: [SlopSign(title: "Comments restate the code", rationale: "The exporter comments every line.")]),
        readingOrder: [ReadingStep(path: "Sources/Billing/InvoiceService.swift", reason: "Core change", isRisky: true)],
        isExpanded: $isExpanded, showsReadingOrder: $showsOrder
    )
    .padding()
    .frame(width: 360)
}
