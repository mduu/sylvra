import DesignSystem
import SwiftUI

/// The round state badge of a box: a filled circle with a white symbol; a running one turns (pure).
struct StateBadge: View {
    let symbol: String
    let tint: Color
    /// Not started yet: an outlined ring instead of a filled circle.
    var isHollow = false
    var isSpinning = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion

    var body: some View {
        ZStack {
            if isHollow {
                Circle().strokeBorder(tint.opacity(0.6), style: StrokeStyle(lineWidth: 1.5, dash: [2.5, 2]))
            } else {
                Circle().fill(tint.gradient)
                    .shadow(color: tint.opacity(0.45), radius: 3, y: 1)
                Image(systemName: symbol)
                    .font(.system(size: 9.5, weight: .heavy))
                    .foregroundStyle(.white)
                    .symbolEffect(.rotate, options: .repeating, isActive: isSpinning && !reduceMotion)
            }
        }
        .frame(width: 20, height: 20)
    }
}

/// One box of the workflow graph (pure): a job with its state and duration — a running or failed one with its
/// step and its steps as small segments — or, for a stage without jobs, the stage itself (waiting for approval,
/// reported as a deployment).
struct JobNodeView: View {
    let job: DeliveryJob?
    let stage: DeliveryStage?
    var isSelected = false
    @Environment(\.accessibilityReduceMotion) private var reduceMotion
    @State private var isPulsing = false

    private var state: StageState { job?.state ?? stage?.state ?? .waiting }

    var body: some View {
        HStack(alignment: .center, spacing: 11) {
            StateBadge(
                symbol: state.badgeSymbol, tint: state.tint, isHollow: state == .waiting,
                isSpinning: state == .running)
            VStack(alignment: .leading, spacing: 3) {
                Text(title)
                    .font(.callout.weight(.semibold))
                    .foregroundStyle(state == .waiting ? .secondary : .primary)
                    // Room for two lines, unless the steps take the third.
                    .lineLimit(showsSteps ? 1 : 2)
                    .truncationMode(.middle)
                    .fixedSize(horizontal: false, vertical: true)
                Text(subtitle)
                    .font(.caption)
                    .foregroundStyle(isAlerting ? state.tint : .secondary)
                    .lineLimit(1)
                    .monospacedDigit()
                if let job, showsSteps { StepSegmentsView(steps: job.steps) }
            }
            Spacer(minLength: 0)
        }
        .padding(.horizontal, 14)
        .padding(.vertical, 10)
        // The box fills its cell: the shape is the cell, not the text.
        .frame(maxWidth: .infinity, maxHeight: .infinity, alignment: .leading)
        .graphBox(isSelected: isSelected, accent: isAlerting ? state.tint : nil, isWaiting: state == .waiting)
        .overlay {
            if state == .running {
                RoundedRectangle(cornerRadius: 14, style: .continuous)
                    .stroke(state.tint.opacity(isPulsing ? 0 : 0.45), lineWidth: 5)
                    .scaleEffect(isPulsing ? 1.05 : 1)
            }
        }
        .help(help)
        .accessibilityElement(children: .combine)
        .onAppear(perform: pulse)
        .onChange(of: state) { pulse() }
    }

    /// Running, failed or waiting for approval: the box takes the state's colour.
    private var isAlerting: Bool { state == .running || state == .failed || state == .needsApproval }

    /// The steps tell something while the job runs or where it broke; all green says nothing new.
    private var showsSteps: Bool {
        guard let job, !job.steps.isEmpty else { return false }
        return job.state == .running || job.state == .failed
    }

    /// A reusable workflow's job ("deploy / deploy-infrastructure"): its own name; the caller goes below.
    private var title: String {
        if let job { return Self.ownName(job.name) }
        guard let stage else { return "" }
        return stage.kind == .environment ? String(localized: "Deploy \(stage.name)") : stage.name
    }

    private var subtitle: String {
        if let failed = job?.steps.first(where: { $0.state == .failed }) {
            return "\(failed.number)/\(job?.steps.count ?? 0) \(failed.name)"
        }
        if let progress = job?.progress {
            return progress.current.map { "\(progress.done + 1)/\(progress.total) \($0)" }
                ?? "\(progress.done)/\(progress.total)"
        }
        if state == .needsApproval { return String(localized: "needs approval") }
        let caller = job.flatMap { Self.caller($0.name) }
        if let duration = job?.duration ?? stage?.duration, state.isFinished {
            return [caller, deliveryDurationText(duration)].compactMap { $0 }.joined(separator: " · ")
        }
        return [caller, state.title.lowercased()].compactMap { $0 }.joined(separator: " · ")
    }

    static func ownName(_ name: String) -> String {
        guard let range = name.range(of: " / ", options: .backwards) else { return name }
        return String(name[range.upperBound...])
    }

    static func caller(_ name: String) -> String? {
        guard let range = name.range(of: " / ", options: .backwards) else { return nil }
        return String(name[..<range.lowerBound])
    }

    private var help: String {
        guard let job, !job.steps.isEmpty else { return title }
        return ([title] + job.steps.map { "\($0.number). \($0.name) — \($0.state.title)" }).joined(separator: "\n")
    }

    private func pulse() {
        isPulsing = false
        guard state == .running, !reduceMotion else { return }
        withAnimation(.easeOut(duration: 1.6).repeatForever(autoreverses: false)) { isPulsing = true }
    }
}

extension View {
    /// The look of a graph box: soft corners, a light fill and shadow; the selected one ringed in the brand colour.
    func graphBox(isSelected: Bool, accent: Color? = nil, isWaiting: Bool = false, isAI: Bool = false) -> some View {
        let shape = RoundedRectangle(cornerRadius: 14, style: .continuous)
        return
            self
            .background {
                ZStack {
                    shape.fill(SylvraColor.surfaceElevated)
                    if isAI { shape.fill(AIAccent.lineGradient(opacity: 0.12)) }
                }
            }
            .overlay {
                if isSelected {
                    shape.strokeBorder(SylvraColor.brandPrimary, lineWidth: 2)
                } else if let accent {
                    shape.strokeBorder(accent.opacity(0.75), lineWidth: 1.4)
                } else if isAI {
                    shape.strokeBorder(AIAccent.border.opacity(0.5), lineWidth: 1)
                } else {
                    shape.strokeBorder(
                        Color.secondary.opacity(isWaiting ? 0.3 : 0.18),
                        style: StrokeStyle(lineWidth: 1, dash: isWaiting ? [4, 3] : []))
                }
            }
            .shadow(color: .black.opacity(isWaiting ? 0 : 0.12), radius: 6, y: 2)
            .contentShape(shape)
    }
}

/// A job's steps as small segments in its box (pure): done green, running violet, failed red, the rest grey.
private struct StepSegmentsView: View {
    let steps: [JobStep]

    var body: some View {
        HStack(spacing: 2) {
            ForEach(steps, id: \.number) { step in
                Capsule().fill(color(step.state)).frame(height: 3)
            }
        }
        .padding(.top, 1)
        .accessibilityHidden(true)
    }

    private func color(_ state: StageState) -> Color {
        switch state {
        case .waiting, .skipped, .cancelled: Color.secondary.opacity(0.3)
        default: state.tint
        }
    }
}

extension StageState {
    /// The symbol inside the round badge.
    var badgeSymbol: String {
        switch self {
        case .waiting: "clock"
        case .needsApproval: "hand.raised.fill"
        case .running: "arrow.triangle.2.circlepath"
        case .succeeded: "checkmark"
        case .failed: "xmark"
        case .cancelled: "minus"
        case .skipped: "arrow.uturn.right"
        }
    }
}

extension StageVerification.Verdict {
    var badgeSymbol: String {
        switch self {
        case .healthy: "checkmark"
        case .problems: "exclamationmark"
        case .unchecked: "questionmark"
        }
    }
}

extension StageVerification.Check.Outcome {
    var badgeSymbol: String {
        switch self {
        case .ok: "checkmark"
        case .problem: "exclamationmark"
        case .unchecked: "questionmark"
        }
    }
}

#Preview {
    let delivery = DemoDeliveryLoader.delivery(for: .init(owner: "acme", repository: "billing", number: 812))
    let jobs = delivery.stages.flatMap(\.jobs)
    VStack(spacing: 12) {
        ForEach(Array(jobs.prefix(2)) + Array(jobs.suffix(2)), id: \.id) { job in
            JobNodeView(job: job, stage: nil).frame(width: 200, height: 76)
        }
        JobNodeView(job: nil, stage: delivery.stages.last, isSelected: true).frame(width: 200, height: 76)
    }
    .padding()
}
