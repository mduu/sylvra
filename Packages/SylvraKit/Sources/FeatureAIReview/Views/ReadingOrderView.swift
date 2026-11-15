import DesignSystem
import SwiftUI
import SylvraCore

/// The AI-suggested reading order with risky areas; a click jumps to the file (pure).
struct ReadingOrderView: View {
    let steps: [ReadingStep]
    let select: (ReadingStep) -> Void

    var body: some View {
        VStack(alignment: .leading, spacing: 6) {
            Text("Suggested reading order").font(.caption.weight(.semibold)).foregroundStyle(.secondary)
            ForEach(Array(steps.enumerated()), id: \.element.path) { index, step in
                Button {
                    select(step)
                } label: {
                    HStack(alignment: .firstTextBaseline, spacing: 8) {
                        Text(verbatim: "\(index + 1)")
                            .font(.system(size: 10, weight: .bold).monospacedDigit())
                            .foregroundStyle(.white)
                            .frame(width: 17, height: 17)
                            .background(AIAccent.border, in: Circle())
                        VStack(alignment: .leading, spacing: 1) {
                            HStack(spacing: 4) {
                                Text((step.path as NSString).lastPathComponent).font(.callout.weight(.medium))
                                if step.isRisky {
                                    Image(systemName: "exclamationmark.triangle.fill")
                                        .font(.caption2)
                                        .foregroundStyle(SylvraColor.accentGold)
                                        .help("Risky area")
                                }
                            }
                            Text(step.reason).font(.caption).foregroundStyle(.secondary)
                        }
                        Spacer(minLength: 0)
                    }
                    .contentShape(Rectangle())
                }
                .buttonStyle(.plain)
            }
        }
        .padding(10)
        .frame(maxWidth: .infinity, alignment: .leading)
        .background(AIAccent.cardBackground, in: RoundedRectangle(cornerRadius: 10))
    }
}

#Preview("Reading order") {
    ReadingOrderView(
        steps: [
            ReadingStep(path: "Sources/Billing/InvoiceService.swift", reason: "Core change", isRisky: true),
            ReadingStep(path: "Sources/Billing/Invoice.swift", reason: "New field"),
        ],
        select: { _ in }
    )
    .frame(width: 300)
    .padding()
}
