import DesignSystem
import SwiftUI

/// The stages of a delivery as connected nodes, left to right (pure). The running stage pulses; a click
/// selects a stage.
struct PipelineStripView: View {
    let stages: [DeliveryStage]
    let selectedID: String?
    let select: (DeliveryStage) -> Void

    var body: some View {
        ScrollView(.horizontal) {
            HStack(alignment: .top, spacing: 0) {
                ForEach(Array(stages.enumerated()), id: \.element.id) { index, stage in
                    if index > 0 {
                        // The way to this stage is "walked" once the stage before is through.
                        Connector(isDone: stages[index - 1].state == .succeeded)
                    }
                    PipelineNodeView(stage: stage, isSelected: stage.id == selectedID) { select(stage) }
                }
            }
            .padding(.vertical, 4)
            .padding(.horizontal, 2)
        }
        .scrollIndicators(.never)
    }

    private struct Connector: View {
        let isDone: Bool

        var body: some View {
            Capsule()
                .fill(isDone ? Color.green.opacity(0.6) : Color.secondary.opacity(0.25))
                .frame(width: 22, height: 2)
                // Level with the centre of the node circles.
                .padding(.top, PipelineNodeView.circleSize / 2 + 5)
                .accessibilityHidden(true)
        }
    }
}

/// One stage in the strip: a state circle with the stage's name and duration below (pure).
struct PipelineNodeView: View {
    static let circleSize: CGFloat = 30

    let stage: DeliveryStage
    let isSelected: Bool
    let select: () -> Void
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    var body: some View {
        Button(action: select) {
            VStack(spacing: 5) {
                ZStack {
                    if stage.state == .running {
                        Circle()
                            .stroke(stage.state.tint.opacity(0.45), lineWidth: 2)
                            .scaleEffect(isPulsing ? 1.35 : 1)
                            .opacity(isPulsing ? 0 : 1)
                    }
                    Circle().fill(stage.state.tint.opacity(stage.state.isFinished ? 0.18 : 0.12))
                    Circle().stroke(stage.state.tint.opacity(0.7), lineWidth: 1.5)
                    Image(systemName: stage.state.symbol)
                        .font(.system(size: 12, weight: .bold))
                        .foregroundStyle(stage.state.tint)
                }
                .frame(width: Self.circleSize, height: Self.circleSize)
                Text(stage.name)
                    .font(.caption.weight(isSelected ? .semibold : .regular))
                    .lineLimit(1)
                Text(detail)
                    .font(.caption2)
                    .foregroundStyle(.secondary)
                    .monospacedDigit()
                    .lineLimit(1)
            }
            .frame(minWidth: 58)
            .padding(.horizontal, 6)
            .padding(.vertical, 5)
            .background(isSelected ? SylvraColor.surfaceSelected : .clear, in: RoundedRectangle(cornerRadius: 8))
            .contentShape(RoundedRectangle(cornerRadius: 8))
        }
        .buttonStyle(.plain)
        .accessibilityLabel("\(stage.name): \(stage.state.title)")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
        .onAppear { startPulse() }
        .onChange(of: stage.state) { startPulse() }
    }

    private var detail: String {
        if let duration = stage.duration, stage.state.isFinished { return deliveryDurationText(duration) }
        return stage.state.title
    }

    private func startPulse() {
        isPulsing = false
        guard stage.state == .running, !reduceMotion else { return }
        withAnimation(.easeOut(duration: 1.4).repeatForever(autoreverses: false)) { isPulsing = true }
    }
}

#Preview {
    @Previewable @State var selected: String?
    let delivery = DemoDeliveryLoader.delivery(for: .init(owner: "acme", repository: "billing", number: 1234))
    PipelineStripView(stages: delivery.stages, selectedID: selected ?? delivery.currentStage?.id) { selected = $0.id }
        .padding()
        .frame(width: 360)
}
