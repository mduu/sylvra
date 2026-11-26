import CoreGraphics
import Foundation

/// Where the boxes and lines of a delivery's graph go, like GitHub draws a workflow run: each band (a stage, or
/// the AI check at the end) with its boxes in columns by what they wait for — splits and joins included — and a
/// line from box edge to box edge. Pure geometry; the view draws the lines as curves and scrolls sideways when
/// the graph is wider than the window.
public struct WorkflowGraphLayout: Equatable, Sendable {
    /// One box to place: what it waits for (ids of other boxes), and whether it is done (its lines are walked).
    public struct Item: Equatable, Sendable {
        public let id: String
        public let needs: [String]
        public let isDone: Bool

        public init(id: String, needs: [String] = [], isDone: Bool = false) {
            self.id = id
            self.needs = needs
            self.isDone = isDone
        }
    }

    /// One band to place: its boxes in columns, left to right.
    public struct Group: Equatable, Sendable {
        public let id: String
        public let columns: [[Item]]
        /// The boxes the line from the band before leads into (`nil`: the first boxes by `needs`).
        public let entries: [String]?

        public init(id: String, columns: [[Item]], entries: [String]? = nil) {
            self.id = id
            self.columns = columns
            self.entries = entries
        }
    }

    public struct Band: Equatable, Sendable, Identifiable {
        public let id: String
        public let frame: CGRect
    }

    public struct Node: Equatable, Sendable, Identifiable {
        public let id: String
        public let bandID: String
        public let frame: CGRect
    }

    public struct Edge: Equatable, Sendable, Identifiable {
        public let id: String
        /// The right edge of the box it leaves and the left edge of the box it enters (middles).
        public let start: CGPoint
        public let end: CGPoint
        /// The box it comes from is done: the way is walked.
        public let isWalked: Bool
    }

    public static let nodeSize = CGSize(width: 160, height: 56)
    static let columnGap: CGFloat = 40
    static let rowGap: CGFloat = 12
    static let bandPadding: CGFloat = 12
    /// Room for the band's name above its boxes.
    static let bandTitle: CGFloat = 34
    static let bandGap: CGFloat = 28

    public let bands: [Band]
    public let nodes: [Node]
    public let edges: [Edge]
    public let size: CGSize

    /// The stages of a delivery, as GitHub reports them.
    public init(stages: [DeliveryStage]) {
        self.init(groups: stages.map(Self.group))
    }

    public init(groups: [Group]) {
        let node = Self.nodeSize
        let rows = max(1, groups.map { $0.columns.map(\.count).max() ?? 1 }.max() ?? 1)
        let contentHeight = CGFloat(rows) * node.height + CGFloat(rows - 1) * Self.rowGap
        let bandHeight = Self.bandTitle + contentHeight + Self.bandPadding
        var bands: [Band] = []
        var nodes: [Node] = []
        var x: CGFloat = 0
        for group in groups {
            let count = max(1, group.columns.count)
            let width = 2 * Self.bandPadding + CGFloat(count) * node.width + CGFloat(count - 1) * Self.columnGap
            bands.append(Band(id: group.id, frame: CGRect(x: x, y: 0, width: width, height: bandHeight)))
            for (column, items) in group.columns.enumerated() {
                let columnHeight = CGFloat(items.count) * node.height + CGFloat(items.count - 1) * Self.rowGap
                var y = Self.bandTitle + (contentHeight - columnHeight) / 2
                let left = x + Self.bandPadding + CGFloat(column) * (node.width + Self.columnGap)
                for item in items {
                    nodes.append(
                        Node(id: item.id, bandID: group.id, frame: CGRect(origin: CGPoint(x: left, y: y), size: node)))
                    y += node.height + Self.rowGap
                }
            }
            x += width + Self.bandGap
        }
        self.bands = bands
        self.nodes = nodes
        self.edges = Self.edges(groups: groups, nodes: nodes)
        self.size = CGSize(width: max(0, x - Self.bandGap), height: bandHeight)
    }

    /// A stage's jobs in columns: a job stands one column right of the last job it waits for in the stage. A
    /// stage without jobs is one box standing for the stage (`stage#<id>`).
    static func group(_ stage: DeliveryStage) -> Group {
        guard !stage.jobs.isEmpty else {
            return Group(id: stage.id, columns: [[Item(id: "stage#\(stage.id)", isDone: stage.state == .succeeded)]])
        }
        let ids = Set(stage.jobs.map(\.id))
        var depth: [String: Int] = [:]
        func depthOf(_ job: DeliveryJob, visiting: Set<String> = []) -> Int {
            if let known = depth[job.id] { return known }
            let value =
                job.needs.filter { ids.contains($0) && !visiting.contains($0) }
                .compactMap { need in stage.jobs.first { $0.id == need } }
                .map { depthOf($0, visiting: visiting.union([job.id])) + 1 }.max() ?? 0
            depth[job.id] = value
            return value
        }
        var columns: [[Item]] = []
        for job in stage.jobs {
            let column = depthOf(job)
            while columns.count <= column { columns.append([]) }
            columns[column].append(Item(id: job.id, needs: job.needs, isDone: job.state == .succeeded))
        }
        return Group(id: stage.id, columns: columns.filter { !$0.isEmpty })
    }

    /// Lines inside a band follow `needs`; between bands they follow `needs` across, or else run from the band's
    /// last boxes to the next band's first.
    static func edges(groups: [Group], nodes: [Node]) -> [Edge] {
        let frames = Dictionary(nodes.map { ($0.id, $0.frame) }, uniquingKeysWith: { first, _ in first })
        var edges: [Edge] = []
        func connect(_ from: Item, _ to: Item) {
            guard let source = frames[from.id], let target = frames[to.id] else { return }
            edges.append(
                Edge(
                    id: "\(from.id)>\(to.id)", start: CGPoint(x: source.maxX, y: source.midY),
                    end: CGPoint(x: target.minX, y: target.midY), isWalked: from.isDone))
        }
        for (index, group) in groups.enumerated() {
            let own = group.columns.flatMap(\.self)
            let byID = Dictionary(own.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            for item in own {
                for need in item.needs { if let from = byID[need] { connect(from, item) } }
            }
            guard index > 0 else { continue }
            let previous = groups[index - 1].columns.flatMap(\.self)
            for (from, to) in crossings(from: previous, to: own, entries: group.entries) { connect(from, to) }
        }
        return edges
    }

    /// The lines from one band into the next: the `needs` that reach back, or else from the band's last boxes to
    /// the next band's first.
    static func crossings(from previous: [Item], to own: [Item], entries: [String]? = nil) -> [(Item, Item)] {
        let ownIDs = Set(own.map(\.id))
        let byID = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let needed = own.flatMap { item in item.needs.compactMap { byID[$0] }.map { ($0, item) } }
        guard needed.isEmpty else { return needed }
        let previousIDs = Set(previous.map(\.id))
        let ends = previous.filter { candidate in
            !previous.contains { $0.needs.contains(candidate.id) && previousIDs.contains($0.id) }
        }
        let starts = own.filter { item in
            entries.map { $0.contains(item.id) } ?? !item.needs.contains { ownIDs.contains($0) }
        }
        return ends.flatMap { from in starts.map { (from, $0) } }
    }
}
