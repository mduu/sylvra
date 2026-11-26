import DesignSystem
import SwiftUI

/// The delivery's workflow as a graph, like GitHub draws a run (pure): each stage a band with its name, the
/// jobs as boxes joined by lines from edge to edge, splits and joins included. Wider than the window, it
/// scrolls sideways and starts at the current stage. A click on a band selects the stage, on a box the job.
struct WorkflowGraphView: View {
    let stages: [DeliveryStage]
    let selectedStageID: String?
    var selectedJobID: String?
    /// The AI check's verdict per stage (`stage.id`).
    var verdicts: [String: StageVerification.Verdict] = [:]
    let selectStage: (DeliveryStage) -> Void
    let selectJob: (DeliveryJob) -> Void

    var body: some View {
        let layout = WorkflowGraphLayout(stages: stages)
        ScrollViewReader { proxy in
            ScrollView(.horizontal) {
                ZStack(alignment: .topLeading) {
                    ForEach(layout.bands) { band in bandView(band) }
                    WorkflowEdgesView(edges: layout.edges)
                        .frame(width: layout.size.width, height: layout.size.height)
                        .allowsHitTesting(false)
                    ForEach(layout.nodes) { node in nodeView(node) }
                }
                .frame(width: layout.size.width, height: layout.size.height, alignment: .topLeading)
                .padding(.horizontal, 16)
                .padding(.vertical, 6)
            }
            .scrollIndicators(.automatic)
            .onAppear { reveal(selectedStageID, proxy) }
            .onChange(of: selectedStageID) { _, id in withAnimation(.snappy) { reveal(id, proxy) } }
        }
    }

    private func reveal(_ stageID: String?, _ proxy: ScrollViewProxy) {
        guard let stageID else { return }
        proxy.scrollTo(stageID, anchor: .center)
    }

    private func bandView(_ band: WorkflowGraphLayout.Band) -> some View {
        let stage = stages.first { $0.id == band.stageID }
        let isSelected = band.stageID == selectedStageID
        return Button {
            if let stage { selectStage(stage) }
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 12)
                    .fill(isSelected ? SylvraColor.surfaceSelected : SylvraColor.surfaceElevated.opacity(0.55))
                RoundedRectangle(cornerRadius: 12)
                    .strokeBorder(
                        isSelected ? SylvraColor.brandPrimary : Color.secondary.opacity(0.25),
                        lineWidth: isSelected ? 1.5 : 1)
                if let stage {
                    BandTitleView(stage: stage, verdict: verdicts[stage.id]).padding(.leading, 12).padding(.top, 9)
                }
            }
            .frame(width: band.frame.width, height: band.frame.height)
            .contentShape(RoundedRectangle(cornerRadius: 12))
        }
        .buttonStyle(.plain)
        .id(band.stageID)
        .offset(x: band.frame.minX, y: band.frame.minY)
        .accessibilityLabel(stage.map { "\($0.name): \($0.state.title)" } ?? "")
        .accessibilityAddTraits(isSelected ? .isSelected : [])
    }

    private func nodeView(_ node: WorkflowGraphLayout.Node) -> some View {
        let stage = stages.first { $0.id == node.stageID }
        return Button {
            if let job = node.job {
                selectJob(job)
            } else if let stage {
                selectStage(stage)
            }
        } label: {
            JobNodeView(
                job: node.job, stage: stage,
                isSelected: node.job.map { $0.id == selectedJobID }
                    ?? (node.stageID == selectedStageID && selectedJobID == nil)
            )
            .frame(width: node.frame.width, height: node.frame.height)
        }
        .buttonStyle(.plain)
        .offset(x: node.frame.minX, y: node.frame.minY)
    }
}

/// The name of a stage above its jobs: duration or state, and the AI check's verdict (pure).
private struct BandTitleView: View {
    let stage: DeliveryStage
    let verdict: StageVerification.Verdict?

    var body: some View {
        HStack(spacing: 6) {
            Text(stage.name).font(.caption.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
            if let verdict {
                Label(verdict.shortTitle, systemImage: verdict.symbol)
                    .labelStyle(.titleAndIcon)
                    .font(.caption2.weight(.semibold))
                    .foregroundStyle(verdict.tint)
                    .padding(.horizontal, 6)
                    .padding(.vertical, 1)
                    .background(verdict.tint.opacity(0.14), in: Capsule())
                    .help(verdict.title)
            }
        }
        .lineLimit(1)
    }

    private var detail: String {
        if let duration = stage.duration, stage.state.isFinished { return deliveryDurationText(duration) }
        if let started = stage.startedAt, stage.state == .running {
            return String(localized: "running \(deliveryDurationText(Date.now.timeIntervalSince(started)))")
        }
        return stage.state.title.lowercased()
    }
}

/// The lines between the boxes (pure): walked ones green, the rest grey.
struct WorkflowEdgesView: View {
    let edges: [WorkflowGraphLayout.Edge]

    var body: some View {
        Canvas { context, _ in
            for walked in [false, true] {
                var path = Path()
                for edge in edges where edge.isWalked == walked {
                    guard let first = edge.points.first else { continue }
                    path.move(to: first)
                    for point in edge.points.dropFirst() { path.addLine(to: point) }
                }
                context.stroke(
                    path, with: .color(walked ? Color.green.opacity(0.75) : Color.secondary.opacity(0.4)),
                    style: StrokeStyle(lineWidth: 1.6, lineCap: .round, lineJoin: .round))
            }
        }
        .accessibilityHidden(true)
    }
}

#Preview {
    @Previewable @State var selected: String?
    let delivery = DemoDeliveryLoader.delivery(for: .init(owner: "acme", repository: "billing", number: 812))
    WorkflowGraphView(
        stages: delivery.stages, selectedStageID: selected ?? delivery.currentStage?.id,
        verdicts: [delivery.stages[1].id: .healthy], selectStage: { selected = $0.id }, selectJob: { _ in }
    )
    .frame(width: 900, height: 280)
}
