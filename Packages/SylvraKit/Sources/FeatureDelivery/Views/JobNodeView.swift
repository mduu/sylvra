import DesignSystem
import SwiftUI

/// One box of the workflow graph (pure): a job with its state and duration — a running job with its step and
/// progress — or, for a stage without jobs, the stage itself (waiting for approval, reported as a deployment).
struct JobNodeView: View {
    let job: DeliveryJob?
    let stage: DeliveryStage?
    var isSelected = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    private var state: StageState { job?.state ?? stage?.state ?? .waiting }

    var body: some View {
        HStack(alignment: .center, spacing: 8) {
            Image(systemName: state.symbol)
                .font(.system(size: 11, weight: .bold))
                .foregroundStyle(state.tint)
                .frame(width: 14)
                .symbolEffect(.rotate, options: .repeating, isActive: state == .running && !reduceMotion)
            VStack(alignment: .leading, spacing: 2) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(state == .waiting ? .secondary : .primary)
                    .lineLimit(1)
                    .truncationMode(.middle)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(state == .needsApproval || state == .running ? state.tint : .secondary)
                    .lineLimit(1)
                    .monospacedDigit()
                if let progress = job?.progress {
                    ProgressView(value: Double(progress.done), total: Double(max(1, progress.total)))
                        .progressViewStyle(.linear)
                        .tint(state.tint)
                        .controlSize(.mini)
                }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 10)
        .background(SylvraColor.surfaceElevated, in: RoundedRectangle(cornerRadius: 8))
        .overlay {
            RoundedRectangle(cornerRadius: 8)
                .strokeBorder(
                    borderColor, style: StrokeStyle(lineWidth: borderWidth, dash: state == .waiting ? [4, 3] : []))
        }
        .overlay {
            if state == .running {
                RoundedRectangle(cornerRadius: 8)
                    .stroke(state.tint.opacity(isPulsing ? 0 : 0.5), lineWidth: 4)
                    .scaleEffect(isPulsing ? 1.06 : 1)
            }
        }
        .contentShape(RoundedRectangle(cornerRadius: 8))
        .help(help)
        .accessibilityElement(children: .combine)
        .onAppear(perform: pulse)
        .onChange(of: state) { pulse() }
    }

    private var title: String {
        if let job { return job.name }
        guard let stage else { return "" }
        return stage.kind == .environment ? String(localized: "Deploy \(stage.name)") : stage.name
    }

    private var subtitle: String {
        if let progress = job?.progress {
            return progress.current.map { "\(progress.done + 1)/\(progress.total) \($0)" }
                ?? "\(progress.done)/\(progress.total)"
        }
        if state == .needsApproval { return String(localized: "needs approval") }
        if let duration = job?.duration ?? stage?.duration, state.isFinished { return deliveryDurationText(duration) }
        return state.title.lowercased()
    }

    private var help: String {
        guard let job, !job.steps.isEmpty else { return title }
        return ([title] + job.steps.map { "\($0.number). \($0.name) — \($0.state.title)" }).joined(separator: "\n")
    }

    private var borderColor: Color {
        if isSelected { return SylvraColor.brandPrimary }
        switch state {
        case .waiting, .skipped, .cancelled: return Color.secondary.opacity(0.35)
        default: return state.tint.opacity(0.8)
        }
    }

    private var borderWidth: CGFloat { isSelected ? 2 : state == .running || state == .failed ? 1.5 : 1 }

    private func pulse() {
        isPulsing = false
        guard state == .running, !reduceMotion else { return }
        withAnimation(.easeOut(duration: 1.5).repeatForever(autoreverses: false)) { isPulsing = true }
    }
}

#Preview {
    let delivery = DemoDeliveryLoader.delivery(for: .init(owner: "acme", repository: "billing", number: 812))
    let jobs = delivery.stages.flatMap(\.jobs)
    VStack(spacing: 12) {
        ForEach(jobs.prefix(3).map(\.self) + jobs.suffix(2).map(\.self), id: \.id) { job in
            JobNodeView(job: job, stage: nil).frame(width: 156, height: 54)
        }
        JobNodeView(job: nil, stage: delivery.stages.last, isSelected: true).frame(width: 156, height: 54)
    }
    .padding()
}
