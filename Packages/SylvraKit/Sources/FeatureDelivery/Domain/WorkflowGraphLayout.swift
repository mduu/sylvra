import CoreGraphics
import Foundation

/// Where the boxes and lines of a delivery's workflow graph go, like GitHub draws a workflow run: each stage a
/// band, its jobs as boxes in columns by what they wait for (splits and joins included), lines from box edge to
/// box edge. Pure geometry; the view only draws it, scrolling sideways when it is wider than the window.
public struct WorkflowGraphLayout: Equatable, Sendable {
    public struct Band: Equatable, Sendable, Identifiable {
        public let stageID: String
        public let frame: CGRect
        public var id: String { stageID }
    }

    public struct Node: Equatable, Sendable, Identifiable {
        public let id: String
        public let stageID: String
        /// The job; `nil` for a stage that has no jobs yet (an environment waiting for approval, a deployment
        /// another system reported).
        public let job: DeliveryJob?
        public let frame: CGRect
    }

    public struct Edge: Equatable, Sendable, Identifiable {
        public let id: String
        /// Corners of the line, start to end (right angles only).
        public let points: [CGPoint]
        /// The job it comes from is done: the way is walked.
        public let isWalked: Bool
    }

    public static let nodeSize = CGSize(width: 156, height: 54)
    static let columnGap: CGFloat = 36
    static let rowGap: CGFloat = 12
    static let bandPadding: CGFloat = 12
    /// Room for the stage's name above its jobs.
    static let bandTitle: CGFloat = 34
    static let bandGap: CGFloat = 20

    public let bands: [Band]
    public let nodes: [Node]
    public let edges: [Edge]
    public let size: CGSize

    public init(stages: [DeliveryStage]) {
        let node = Self.nodeSize
        // Columns and rows per stage, from the jobs' `needs` inside the stage.
        let grids = stages.map(Self.grid)
        let rows = max(1, grids.map { $0.map(\.count).max() ?? 1 }.max() ?? 1)
        let contentHeight = CGFloat(rows) * node.height + CGFloat(rows - 1) * Self.rowGap
        let bandHeight = Self.bandTitle + contentHeight + Self.bandPadding
        var bands: [Band] = []
        var nodes: [Node] = []
        var x: CGFloat = 0
        for (stage, columns) in zip(stages, grids) {
            let width =
                2 * Self.bandPadding + CGFloat(columns.count) * node.width
                + CGFloat(max(0, columns.count - 1)) * Self.columnGap
            bands.append(Band(stageID: stage.id, frame: CGRect(x: x, y: 0, width: width, height: bandHeight)))
            for (column, entries) in columns.enumerated() {
                let columnHeight = CGFloat(entries.count) * node.height + CGFloat(entries.count - 1) * Self.rowGap
                var y = Self.bandTitle + (contentHeight - columnHeight) / 2
                let left = x + Self.bandPadding + CGFloat(column) * (node.width + Self.columnGap)
                for job in entries {
                    nodes.append(
                        Node(
                            id: job?.id ?? "stage#\(stage.id)", stageID: stage.id, job: job,
                            frame: CGRect(origin: CGPoint(x: left, y: y), size: node)))
                    y += node.height + Self.rowGap
                }
            }
            x += width + Self.bandGap
        }
        self.bands = bands
        self.nodes = nodes
        self.edges = Self.edges(stages: stages, nodes: nodes, bands: bands)
        self.size = CGSize(width: max(0, x - Self.bandGap), height: bandHeight)
    }

    /// A stage's jobs in columns: a job stands one column right of the last job it waits for in the stage.
    static func grid(_ stage: DeliveryStage) -> [[DeliveryJob?]] {
        guard !stage.jobs.isEmpty else { return [[nil]] }
        let ids = Set(stage.jobs.map(\.id))
        var depth: [String: Int] = [:]
        func depthOf(_ job: DeliveryJob, visiting: Set<String> = []) -> Int {
            if let known = depth[job.id] { return known }
            let needs = job.needs.filter { ids.contains($0) && !visiting.contains($0) }
            let value =
                needs.compactMap { need in stage.jobs.first { $0.id == need } }
                .map { depthOf($0, visiting: visiting.union([job.id])) + 1 }.max() ?? 0
            depth[job.id] = value
            return value
        }
        var columns: [[DeliveryJob?]] = []
        for job in stage.jobs {
            let column = depthOf(job)
            while columns.count <= column { columns.append([]) }
            columns[column].append(job)
        }
        return columns.filter { !$0.isEmpty }
    }

    /// Lines inside a stage follow `needs`; between stages they follow `needs` across, or else run from the
    /// stage's last jobs to the next stage's first.
    static func edges(stages: [DeliveryStage], nodes: [Node], bands: [Band]) -> [Edge] {
        let byID = Dictionary(nodes.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        var edges: [Edge] = []
        func connect(_ from: Node, _ to: Node, viaX: CGFloat) {
            let start = CGPoint(x: from.frame.maxX, y: from.frame.midY)
            let end = CGPoint(x: to.frame.minX, y: to.frame.midY)
            let points =
                start.y == end.y
                ? [start, end] : [start, CGPoint(x: viaX, y: start.y), CGPoint(x: viaX, y: end.y), end]
            edges.append(Edge(id: "\(from.id)>\(to.id)", points: points, isWalked: from.job?.state == .succeeded))
        }
        for (index, stage) in stages.enumerated() {
            let own = nodes.filter { $0.stageID == stage.id }
            let ownIDs = Set(own.map(\.id))
            for node in own {
                for need in node.job?.needs ?? [] where ownIDs.contains(need) {
                    guard let from = byID[need] else { continue }
                    connect(from, node, viaX: from.frame.maxX + columnGap / 2)
                }
            }
            guard index > 0 else { continue }
            let previous = nodes.filter { $0.stageID == stages[index - 1].id }
            let gapX = bands[index].frame.minX - bandGap / 2
            for (from, to) in crossings(from: previous, to: own) { connect(from, to, viaX: gapX) }
        }
        return edges
    }

    /// The lines from one stage into the next: the `needs` that reach back, or else from the stage's last jobs to
    /// the next stage's first.
    static func crossings(from previous: [Node], to own: [Node]) -> [(Node, Node)] {
        let ownIDs = Set(own.map(\.id))
        let byID = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let needed = own.flatMap { node in (node.job?.needs ?? []).compactMap { byID[$0] }.map { ($0, node) } }
        guard needed.isEmpty else { return needed }
        let previousIDs = Set(previous.map(\.id))
        let ends = previous.filter { candidate in
            !previous.contains { $0.job?.needs.contains(candidate.id) == true && previousIDs.contains($0.id) }
        }
        let starts = own.filter { node in !(node.job?.needs.contains { ownIDs.contains($0) } ?? false) }
        return ends.flatMap { from in starts.map { (from, $0) } }
    }
}
