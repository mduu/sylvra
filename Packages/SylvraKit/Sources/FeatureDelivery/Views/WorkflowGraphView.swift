import DesignSystem
import SwiftUI

/// The delivery as a graph, like GitHub draws a workflow run (pure): each stage a band with its jobs as boxes,
/// joined by curved lines from box to box — splits and joins included. At the end, joined by a dashed line (an
/// assessment, not a step), the AI check's verdict card. Wider than the window, it scrolls sideways and starts at
/// the selection.
struct WorkflowGraphView<Card: View>: View {
    let stages: [DeliveryStage]
    /// The selected band: a stage's id, or `ai#<stage id>` for a stage's AI check (then the card is selected).
    let selectedBandID: String?
    /// The selected job's id.
    var selectedBoxID: String?
    let selectStage: (DeliveryStage) -> Void
    let selectJob: (DeliveryJob) -> Void
    /// The AI check's card (`nil`: no AI check).
    var card: Card?
    var cardHeight: CGFloat = 0

    /// Where the user scrolled to; only ever changed sideways by Sylvra.
    @State private var position = ScrollPosition()
    @State private var visible: CGRect = .zero

    static var cardID: String { "ai-card" }
    static var cardWidth: CGFloat { 540 }
    static var cardGap: CGFloat { 64 }

    var body: some View {
        let layout = WorkflowGraphLayout(stages: stages)
        let height = max(layout.size.height, card == nil ? 0 : cardHeight)
        let width = layout.size.width + (card == nil ? 0 : Self.cardGap + Self.cardWidth)
        // Sideways for long pipelines, down for stages with many jobs (the details keep their room).
        ScrollView([.horizontal, .vertical]) {
            ZStack(alignment: .topLeading) {
                ForEach(layout.bands) { band in bandView(band) }
                WorkflowEdgesView(edges: layout.edges)
                    .frame(width: layout.size.width, height: layout.size.height)
                    .allowsHitTesting(false)
                ForEach(layout.nodes) { node in nodeView(node) }
                if let card {
                    DashedConnector()
                        .stroke(AIAccent.border.opacity(0.8), style: StrokeStyle(lineWidth: 1.8, dash: [5, 4]))
                        .frame(width: Self.cardGap, height: 12)
                        .offset(x: layout.size.width, y: layout.size.height / 2 - 6)
                        .accessibilityHidden(true)
                    card
                        .frame(width: Self.cardWidth, height: height)
                        .id(Self.cardID)
                        .offset(x: layout.size.width + Self.cardGap)
                }
            }
            .frame(width: width, height: height, alignment: .topLeading)
            .padding(.horizontal, 16)
            .padding(.vertical, 6)
        }
        .scrollIndicators(.automatic)
        .scrollPosition($position)
        .onScrollGeometryChange(for: CGRect.self) {
            $0.visibleRect
        } action: { _, rect in
            visible = rect
        }
        .onAppear { reveal(in: layout, animated: false) }
        .onChange(of: selectedBandID) { reveal(in: layout, animated: true) }
    }

    /// Brings the selected stage (or the AI check's card) into view sideways — only when it is not visible
    /// already, and never up or down: the user's vertical position stays.
    private func reveal(in layout: WorkflowGraphLayout, animated: Bool) {
        guard let selectedBandID else { return }
        let padding: CGFloat = 16
        let frame: CGRect
        if selectedBandID.hasPrefix(DeliveryModel.aiPrefix) {
            frame = CGRect(x: layout.size.width + Self.cardGap, y: 0, width: Self.cardWidth, height: 1)
        } else if let band = layout.bands.first(where: { $0.id == selectedBandID }) {
            frame = band.frame
        } else {
            return
        }
        let left = frame.minX + padding
        let right = frame.maxX + padding
        guard visible.width > 0, left < visible.minX || right > visible.maxX else { return }
        let target = max(0, left - max(0, (visible.width - frame.width) / 2))
        let point = CGPoint(x: target, y: visible.minY)
        if animated {
            withAnimation(.snappy) { position.scrollTo(point: point) }
        } else {
            position.scrollTo(point: point)
        }
    }

    private func bandView(_ band: WorkflowGraphLayout.Band) -> some View {
        let stage = stages.first { $0.id == band.id }
        let selected = band.id == selectedBandID
        return Button {
            if let stage { selectStage(stage) }
        } label: {
            ZStack(alignment: .topLeading) {
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .fill(selected ? SylvraColor.surfaceSelected : SylvraColor.surfaceElevated.opacity(0.5))
                RoundedRectangle(cornerRadius: 16, style: .continuous)
                    .strokeBorder(
                        selected ? SylvraColor.brandPrimary : Color.secondary.opacity(0.2),
                        lineWidth: selected ? 1.5 : 1)
                if let stage { StageBandTitle(stage: stage).padding(.leading, 14).padding(.top, 10) }
            }
            .frame(width: band.frame.width, height: band.frame.height)
            .contentShape(RoundedRectangle(cornerRadius: 16, style: .continuous))
        }
        .buttonStyle(.plain)
        .id(band.id)
        .offset(x: band.frame.minX, y: band.frame.minY)
        .accessibilityLabel(stage.map { "\($0.name): \($0.state.title)" } ?? "")
        .accessibilityAddTraits(selected ? .isSelected : [])
    }

    private func nodeView(_ node: WorkflowGraphLayout.Node) -> some View {
        let stage = stages.first { $0.id == node.bandID }
        let job = stage?.jobs.first { $0.id == node.id }
        return Button {
            if let job {
                selectJob(job)
            } else if let stage {
                selectStage(stage)
            }
        } label: {
            JobNodeView(
                job: job, stage: stage,
                isSelected: job.map { $0.id == selectedBoxID } ?? (stage?.id == selectedBandID && selectedBoxID == nil)
            )
            .frame(width: node.frame.width, height: node.frame.height)
        }
        .buttonStyle(.plain)
        .offset(x: node.frame.minX, y: node.frame.minY)
    }
}

/// A horizontal line with a dot at its end (the dashed join to the AI check's card).
private struct DashedConnector: Shape {
    func path(in rect: CGRect) -> Path {
        var path = Path()
        path.move(to: CGPoint(x: rect.minX, y: rect.midY))
        path.addLine(to: CGPoint(x: rect.maxX - 6, y: rect.midY))
        path.addEllipse(in: CGRect(x: rect.maxX - 8, y: rect.midY - 4, width: 8, height: 8))
        return path
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
/// green, the rest grey. Where lines gather, a ringed junction.
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
                    if !edge.startsAtJunction { dots.addEllipse(in: Self.dot(edge.start, size: 6)) }
                    if !edge.endsAtJunction { dots.addEllipse(in: Self.dot(edge.end, size: 6)) }
                }
                context.stroke(path, with: .color(color), style: StrokeStyle(lineWidth: 1.8, lineCap: .round))
                context.fill(dots, with: .color(color))
            }
            var junctions = Set<PointKey>()
            for edge in edges {
                if edge.endsAtJunction { junctions.insert(PointKey(edge.end)) }
                if edge.startsAtJunction { junctions.insert(PointKey(edge.start)) }
            }
            for key in junctions {
                let walked = edges.contains { $0.startsAtJunction && PointKey($0.start) == key && $0.isWalked }
                let circle = Path(ellipseIn: Self.dot(key.point, size: 10))
                context.fill(circle, with: .color(walked ? Color.green : Color.secondary.opacity(0.6)))
                context.stroke(circle, with: .color(.white.opacity(0.5)), lineWidth: 1.5)
            }
        }
        .accessibilityHidden(true)
    }

    static func dot(_ point: CGPoint, size: CGFloat) -> CGRect {
        CGRect(x: point.x - size / 2, y: point.y - size / 2, width: size, height: size)
    }

    /// A point as a set member (junctions shared by several lines).
    struct PointKey: Hashable {
        let x: CGFloat
        let y: CGFloat
        init(_ point: CGPoint) {
            x = point.x
            y = point.y
        }
        var point: CGPoint { CGPoint(x: x, y: y) }
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
    WorkflowGraphView<EmptyView>(
        stages: delivery.stages, selectedBandID: selected ?? delivery.currentStage?.id,
        selectStage: { selected = $0.id },
        selectJob: { _ in }
    )
    .frame(width: 1100, height: 300)
}
