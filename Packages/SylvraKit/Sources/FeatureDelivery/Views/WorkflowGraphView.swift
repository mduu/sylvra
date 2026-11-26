import DesignSystem
import SwiftUI

/// The delivery as a graph, like GitHub draws a workflow run (pure): each stage a band with its jobs as boxes,
/// joined by curved lines from box to box — splits and joins included — and at the end the AI check, a band with
/// a column of checks per checked stage. Wider than the window, it scrolls sideways and starts at the selection.
struct WorkflowGraphView: View {
    let stages: [DeliveryStage]
    var aiColumns: [AICheckColumn] = []
    /// The selected band: a stage's id, or `ai#<stage id>` for a stage's AI check.
    let selectedBandID: String?
    /// The selected box's id (a job, or `ai#<stage id>#<check>`).
    var selectedBoxID: String?
    let selectStage: (DeliveryStage) -> Void
    let selectJob: (DeliveryJob) -> Void
    /// A box of the AI check band: the stage and, for a check's box, its title.
    var selectAICheck: (DeliveryStage, String?) -> Void = { _, _ in }

    static let aiBandID = "ai"

    var body: some View {
        let layout = WorkflowGraphLayout(groups: groups)
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
            .onAppear { reveal(proxy) }
            .onChange(of: selectedBandID) { withAnimation(.snappy) { reveal(proxy) } }
        }
    }

    private var groups: [WorkflowGraphLayout.Group] {
        var groups = stages.map(WorkflowGraphLayout.group)
        if !aiColumns.isEmpty {
            let columns = aiColumns.map { column in
                column.boxIDs.map { WorkflowGraphLayout.Item(id: $0, isDone: column.result != nil) }
            }
            groups.append(
                WorkflowGraphLayout.Group(id: Self.aiBandID, columns: columns, entries: columns.first?.map(\.id)))
        }
        return groups
    }

    private func reveal(_ proxy: ScrollViewProxy) {
        guard let selectedBandID else { return }
        proxy.scrollTo(
            selectedBandID.hasPrefix(DeliveryModel.aiPrefix) ? Self.aiBandID : selectedBandID, anchor: .center)
    }

    private func isSelected(_ band: WorkflowGraphLayout.Band) -> Bool {
        band.id == Self.aiBandID ? selectedBandID?.hasPrefix(DeliveryModel.aiPrefix) == true : band.id == selectedBandID
    }

    private func bandView(_ band: WorkflowGraphLayout.Band) -> some View {
        let stage = stages.first { $0.id == band.id }
        let isAI = band.id == Self.aiBandID
        let selected = isSelected(band)
        return Button {
            if let stage {
                selectStage(stage)
            } else if isAI, let first = aiColumns.first {
                selectAICheck(first.stage, nil)
            }
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(
                        isAI
                            ? AnyShapeStyle(AIAccent.lineGradient(opacity: selected ? 0.16 : 0.08))
                            : AnyShapeStyle(bandFill(selected)))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(bandBorder(isAI: isAI, selected: selected), lineWidth: selected ? 1.5 : 1)
                Group {
                    if let stage {
                        StageBandTitle(stage: stage)
                    } else if isAI {
                        Label("AI check", systemImage: "sparkles")
                            .font(.caption.weight(.bold))
                            .foregroundStyle(AIAccent.border)
                    }
                }
                .padding(.leading, 14)
                .padding(.top, 10)
            }
            .frame(width: band.frame.width, height: band.frame.height)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .id(band.id)
        .offset(x: band.frame.minX, y: band.frame.minY)
        .accessibilityLabel(stage.map { "\($0.name): \($0.state.title)" } ?? String(localized: "AI check"))
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func bandFill(_ selected: Bool) -> Color {
        selected ? SylvraColor.surfaceSelected : SylvraColor.surfaceElevated.opacity(0.5)
    }

    private func bandBorder(isAI: Bool, selected: Bool) -> AnyShapeStyle {
        if isAI { return AnyShapeStyle(AIAccent.border.opacity(selected ? 0.9 : 0.45)) }
        return AnyShapeStyle(selected ? SylvraColor.brandPrimary : Color.secondary.opacity(0.2))
    }

    @ViewBuilder private func nodeView(_ node: WorkflowGraphLayout.Node) -> some View {
        if node.bandID == Self.aiBandID {
            aiNodeView(node)
        } else {
            let stage = stages.first { $0.id == node.bandID }
            let job = stage?.jobs.first { $0.id == node.id }
            Button {
                if let job {
                    selectJob(job)
                } else if let stage {
                    selectStage(stage)
                }
            } label: {
                JobNodeView(
                    job: job, stage: stage,
                    isSelected: job.map { $0.id == selectedBoxID }
                        ?? (stage?.id == selectedBandID && selectedBoxID == nil)
                )
                .frame(width: node.frame.width, height: node.frame.height)
            }
            .buttonStyle(.plain)
            .offset(x: node.frame.minX, y: node.frame.minY)
        }
    }

    @ViewBuilder private func aiNodeView(_ node: WorkflowGraphLayout.Node) -> some View {
        if let column = aiColumns.first(where: { node.id.hasPrefix("ai#\($0.stage.id)#") }) {
            let title = String(node.id.dropFirst("ai#\(column.stage.id)#".count))
            let check = column.result?.checks.first { $0.title == title }
            Button {
                selectAICheck(column.stage, check?.title)
            } label: {
                AICheckNodeView(
                    column: column, check: check,
                    isSelected: node.id == selectedBoxID
                        || (check == nil && selectedBandID == DeliveryModel.aiPrefix + column.stage.id)
                )
                .frame(width: node.frame.width, height: node.frame.height)
            }
            .buttonStyle(.plain)
            .offset(x: node.frame.minX, y: node.frame.minY)
        }
    }
}

/// The name of a stage above its jobs, with its duration or state (pure).
private struct StageBandTitle: View {
    let stage: DeliveryStage

    var body: some View {
        HStack(spacing: 6) {
            Text(stage.name).font(.caption.weight(.semibold))
            Text(detail).font(.caption).foregroundStyle(.secondary).monospacedDigit()
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

/// The lines between the boxes (pure): smooth curves from box to box with a dot at each end; walked ones
/// green, the rest grey.
struct WorkflowEdgesView: View {
    let edges: [WorkflowGraphLayout.Edge]

    var body: some View {
        Canvas { context, _ in
            for walked in [false, true] {
                let color = walked ? Color.green.opacity(0.7) : Color.secondary.opacity(0.35)
                var path = Path()
                var dots = Path()
                for edge in edges where edge.isWalked == walked {
                    path.addPath(Self.curve(edge))
                    for point in [edge.start, edge.end] {
                        dots.addEllipse(in: CGRect(x: point.x - 3, y: point.y - 3, width: 6, height: 6))
                    }
                }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                context.fill(dots, with: .color(color))
            }
        }
        .accessibilityHidden(true)
    }

    /// An S-curve: leaves and enters horizontally, the bend spread over the gap.
    static func curve(_ edge: WorkflowGraphLayout.Edge) -> Path {
        var path = Path()
        path.move(to: edge.start)
        let pull = max(24, (edge.end.x - edge.start.x) * 0.5)
        path.addCurve(
            to: edge.end, control1: CGPoint(x: edge.start.x + pull, y: edge.start.y),
            control2: CGPoint(x: edge.end.x - pull, y: edge.end.y))
        return path
    }
}

#Preview {
    @Previewable @State var selected: String?
    let delivery = DemoDeliveryLoader.delivery(for: .init(owner: "acme", repository: "billing", number: 812))
    let dev = delivery.stages[1]
    WorkflowGraphView(
        stages: delivery.stages,
        aiColumns: [
            AICheckColumn(
                stage: dev, result: DemoDeliveryVerifier.verification(for: dev), isRunning: false, error: nil,
                isCheckable: true)
        ],
        selectedBandID: selected ?? delivery.currentStage?.id, selectStage: { selected = $0.id }, selectJob: { _ in }
    )
    .frame(width: 1100, height: 300)
}
