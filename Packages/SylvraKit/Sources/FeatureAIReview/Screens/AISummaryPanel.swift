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
                summary: result.summary, readingOrder: result.readingOrder, isExpanded: $isExpanded,
                showsReadingOrder: $showsReadingOrder, openFile: openFile)
        }
    }
}

/// Summary text (collapsed to a few lines) and the reading order on demand (pure).
struct AISummaryCardView: View {
    let summary: String
    let readingOrder: [ReadingStep]
    @Binding var isExpanded: Bool
    @Binding var showsReadingOrder: Bool
    var openFile: (String) -> Void = { _ in }

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            HStack {
                Label("AI summary", systemImage: "sparkles")
                    .font(.caption.weight(.semibold))
                    .foregroundStyle(AIAccent.border)
                Spacer()
                Button(isExpanded ? "Less" : "More") { withAnimation(.snappy) { isExpanded.toggle() } }
                    .buttonStyle(.link)
                    .font(.caption)
            }
            Text(summary)
                .font(.callout)
                .lineLimit(isExpanded ? nil : 3)
                .textSelection(.enabled)
                .fixedSize(horizontal: false, vertical: true)
            if !readingOrder.isEmpty {
                DisclosureGroup(isExpanded: $showsReadingOrder) {
                    ReadingOrderView(steps: readingOrder) { openFile($0.path) }
                        .padding(.top, 4)
                } label: {
                    Text("Reading order (\(readingOrder.count) files)").font(.caption).foregroundStyle(.secondary)
                }
            }
        }
        .padding(10)
        .background(AIAccent.lineGradient(opacity: 0.12), in: RoundedRectangle(cornerRadius: 10))
        .overlay(RoundedRectangle(cornerRadius: 10).strokeBorder(AIAccent.border.opacity(0.45)))
    }
}

#Preview {
    @Previewable @State var isExpanded = false
    @Previewable @State var showsOrder = false
    AISummaryCardView(
        summary: "Adds CSV export next to JSON and changes how invoice totals are rounded (per line instead of "
            + "once). The rounding change affects every invoice total; the export is additive.",
        readingOrder: [ReadingStep(path: "Sources/Billing/InvoiceService.swift", reason: "Core change", isRisky: true)],
        isExpanded: $isExpanded, showsReadingOrder: $showsOrder
    )
    .padding()
    .frame(width: 360)
}
