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

        public init(id: String, columns: [[Item]]) {
            self.id = id
            self.columns = columns
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
        /// The line starts or ends at a junction (many lines gathered into one point), not at a box.
        public var startsAtJunction = false
        public var endsAtJunction = false
    }

    public static let nodeSize = CGSize(width: 200, height: 76)
    static let columnGap: CGFloat = 64
    static let rowGap: CGFloat = 14
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
            let boxWidth = node.width
            let width = 2 * Self.bandPadding + CGFloat(count) * boxWidth + CGFloat(count - 1) * Self.columnGap
            bands.append(Band(id: group.id, frame: CGRect(x: x, y: 0, width: width, height: bandHeight)))
            for (column, items) in group.columns.enumerated() {
                let columnHeight = CGFloat(items.count) * node.height + CGFloat(items.count - 1) * Self.rowGap
                var y = Self.bandTitle + (contentHeight - columnHeight) / 2
                let left = x + Self.bandPadding + CGFloat(column) * (boxWidth + Self.columnGap)
                for item in items {
                    let frame = CGRect(x: left, y: y, width: boxWidth, height: node.height)
                    nodes.append(Node(id: item.id, bandID: group.id, frame: frame))
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
        for (index, group) in groups.enumerated() {
            let own = group.columns.flatMap(\.self)
            let byID = Dictionary(own.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
            let inside = own.flatMap { item in item.needs.compactMap { byID[$0] }.map { ($0, item) } }
            edges += route(inside, frames: frames)
            guard index > 0 else { continue }
            let previous = groups[index - 1].columns.flatMap(\.self)
            edges += route(crossings(from: previous, to: own), frames: frames)
        }
        return edges
    }

    /// Lines for pairs of boxes. Where several boxes all wait for the same several boxes (every test job for
    /// every build job), the lines gather in a junction between them instead of crossing each other n × m times.
    static func route(_ pairs: [(Item, Item)], frames: [String: CGRect]) -> [Edge] {
        var sourcesOf: [String: [Item]] = [:]
        var targets: [Item] = []
        for (from, to) in pairs {
            if sourcesOf[to.id] == nil { targets.append(to) }
            if sourcesOf[to.id]?.contains(where: { $0.id == from.id }) != true {
                sourcesOf[to.id, default: []].append(from)
            }
        }
        // Targets by the set of boxes they wait for.
        var clusters: [[String]: [Item]] = [:]
        var order: [[String]] = []
        for target in targets {
            let key = (sourcesOf[target.id] ?? []).map(\.id).sorted()
            if clusters[key] == nil { order.append(key) }
            clusters[key, default: []].append(target)
        }
        return order.flatMap { key -> [Edge] in
            let members = clusters[key] ?? []
            let sources = members.first.flatMap { sourcesOf[$0.id] } ?? []
            if sources.count > 1, members.count > 1 {
                return junction(from: sources, to: members, key: key, frames: frames)
            }
            return members.flatMap { target in
                sources.compactMap { source -> Edge? in
                    guard let from = frames[source.id], let to = frames[target.id] else { return nil }
                    return Edge(
                        id: "\(source.id)>\(target.id)", start: CGPoint(x: from.maxX, y: from.midY),
                        end: CGPoint(x: to.minX, y: to.midY), isWalked: source.isDone)
                }
            }
        }
    }

    /// Lines from every source into one point between the boxes, and from there to every target.
    private static func junction(from sources: [Item], to targets: [Item], key: [String], frames: [String: CGRect])
        -> [Edge]
    {
        let sourceFrames = sources.compactMap { frames[$0.id] }
        let targetFrames = targets.compactMap { frames[$0.id] }
        guard let right = sourceFrames.map(\.maxX).max(), let left = targetFrames.map(\.minX).min() else { return [] }
        let middles = (sourceFrames + targetFrames).map(\.midY)
        let point = CGPoint(x: (right + left) / 2, y: middles.reduce(0, +) / CGFloat(middles.count))
        let name = "junction(\(key.joined(separator: ",")))"
        var edges: [Edge] = []
        for (source, frame) in zip(sources, sourceFrames) {
            var edge = Edge(
                id: "\(source.id)>\(name)", start: CGPoint(x: frame.maxX, y: frame.midY), end: point,
                isWalked: source.isDone)
            edge.endsAtJunction = true
            edges.append(edge)
        }
        let allDone = sources.allSatisfy(\.isDone)
        for (target, frame) in zip(targets, targetFrames) {
            var edge = Edge(
                id: "\(name)>\(target.id)", start: point, end: CGPoint(x: frame.minX, y: frame.midY), isWalked: allDone)
            edge.startsAtJunction = true
            edges.append(edge)
        }
        return edges
    }

    /// The lines from one band into the next: the `needs` that reach back, or else from the band's last boxes to
    /// the next band's first.
    static func crossings(from previous: [Item], to own: [Item]) -> [(Item, Item)] {
        let ownIDs = Set(own.map(\.id))
        let byID = Dictionary(previous.map { ($0.id, $0) }, uniquingKeysWith: { first, _ in first })
        let needed = own.flatMap { item in item.needs.compactMap { byID[$0] }.map { ($0, item) } }
        guard needed.isEmpty else { return needed }
        let previousIDs = Set(previous.map(\.id))
        let ends = previous.filter { candidate in
            !previous.contains { $0.needs.contains(candidate.id) && previousIDs.contains($0.id) }
        }
        let starts = own.filter { item in !item.needs.contains { ownIDs.contains($0) } }
        return ends.flatMap { from in starts.map { (from, $0) } }
    }
}
