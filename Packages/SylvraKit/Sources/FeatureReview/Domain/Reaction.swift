import Foundation

/// A GitHub reaction (`ReactionContent`).
public enum Reaction: String, CaseIterable, Identifiable, Sendable {
    case thumbsUp = "THUMBS_UP"
    case thumbsDown = "THUMBS_DOWN"
    case laugh = "LAUGH"
    case hooray = "HOORAY"
    case confused = "CONFUSED"
    case heart = "HEART"
    case rocket = "ROCKET"
    case eyes = "EYES"

    public var id: String { rawValue }

    public var emoji: String {
        switch self {
        case .thumbsUp: "👍"
        case .thumbsDown: "👎"
        case .laugh: "😄"
        case .hooray: "🎉"
        case .confused: "😕"
        case .heart: "❤️"
        case .rocket: "🚀"
        case .eyes: "👀"
        }
    }
}

/// How often a reaction was given to a comment, and whether the viewer gave it.
public struct ReactionGroup: Hashable, Sendable {
    public let reaction: Reaction
    public var count: Int
    public var viewerHasReacted: Bool

    public init(reaction: Reaction, count: Int, viewerHasReacted: Bool = false) {
        self.reaction = reaction
        self.count = count
        self.viewerHasReacted = viewerHasReacted
    }
}

extension [ReactionGroup] {
    /// Adds or removes the viewer's reaction; empty groups disappear, order follows GitHub's.
    public func toggling(_ reaction: Reaction) -> [ReactionGroup] {
        var groups = self
        if let index = groups.firstIndex(where: { $0.reaction == reaction }) {
            let adding = !groups[index].viewerHasReacted
            groups[index].viewerHasReacted = adding
            groups[index].count += adding ? 1 : -1
            if groups[index].count < 1 { groups.remove(at: index) }
        } else {
            groups.append(ReactionGroup(reaction: reaction, count: 1, viewerHasReacted: true))
        }
        let order = Reaction.allCases
        return groups.sorted { order.firstIndex(of: $0.reaction) ?? 0 < order.firstIndex(of: $1.reaction) ?? 0 }
    }
}
