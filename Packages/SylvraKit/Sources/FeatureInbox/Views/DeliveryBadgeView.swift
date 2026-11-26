import DesignSystem
import SwiftUI
import SylvraCore

/// A merged pull request's delivery in an inbox row (pure): the stages as joined dots, then the outcome —
/// a green check when it is live and healthy, a red exclamation mark on a problem.
struct DeliveryBadgeView: View {
    let badge: DeliveryBadge

    var body: some View {
        HStack(spacing: 6) {
            HStack(spacing: 0) {
                ForEach(Array(badge.dots.enumerated()), id: \.offset) { index, dot in
                    if index > 0 {
                        Rectangle()
                            .fill(
                                badge.dots[index - 1] == .done ? Color.green.opacity(0.7) : Color.secondary.opacity(0.3)
                            )
                            .frame(width: 8, height: 1.5)
                    }
                    dotView(dot)
                }
            }
            outcome
            Text(badge.text).lineLimit(1)
        }
        .font(.caption)
        .foregroundStyle(textColor)
        .accessibilityElement(children: .ignore)
        .accessibilityLabel(badge.text)
    }

    @ViewBuilder private func dotView(_ dot: DeliveryBadge.Dot) -> some View {
        switch dot {
        case .done: Circle().fill(Color.green).frame(width: 7, height: 7)
        case .failed: Circle().fill(SylvraColor.statusCritical).frame(width: 7, height: 7)
        case .running:
            Circle().fill(SylvraColor.brandPrimary).frame(width: 7, height: 7)
                .overlay(Circle().stroke(SylvraColor.brandPrimary.opacity(0.35), lineWidth: 3))
        case .needsApproval: Circle().strokeBorder(SylvraColor.statusWarning, lineWidth: 1.5).frame(width: 7, height: 7)
        case .waiting, .skipped:
            Circle().strokeBorder(Color.secondary.opacity(0.5), lineWidth: 1.2).frame(width: 7, height: 7)
        }
    }

    @ViewBuilder private var outcome: some View {
        switch badge.outcome {
        case .healthy: Image(systemName: "checkmark.circle.fill").foregroundStyle(.green)
        case .problem: Image(systemName: "exclamationmark.circle.fill").foregroundStyle(SylvraColor.statusCritical)
        case .inProgress: EmptyView()
        }
    }

    private var textColor: Color {
        switch badge.outcome {
        case .healthy: .green
        case .problem: SylvraColor.statusCritical
        case .inProgress: .secondary
        }
    }
}

#Preview {
    VStack(alignment: .leading, spacing: 10) {
        DeliveryBadgeView(
            badge: .init(dots: [.done, .done, .running, .needsApproval], outcome: .inProgress, text: "test is running"))
        DeliveryBadgeView(badge: .init(dots: [.done, .done, .done, .done], outcome: .healthy, text: "Live · healthy"))
        DeliveryBadgeView(
            badge: .init(dots: [.done, .failed, .waiting, .waiting], outcome: .problem, text: "dev failed"))
    }
    .padding()
}
