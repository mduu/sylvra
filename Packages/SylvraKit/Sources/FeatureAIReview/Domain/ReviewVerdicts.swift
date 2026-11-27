import Foundation

/// Whether the pull request can be merged as it is — its quality, independent of how risky merging is.
public enum Mergeability: String, Codable, Sendable, CaseIterable, Comparable {
    // Worst first: with several shards or models the lowest rating wins.
    case notMergeable, acceptable, good, excellent

    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// The review's merge verdict with its main reasons (the blockers when not mergeable).
public struct MergeabilityAssessment: Hashable, Sendable, Codable {
    public var level: Mergeability
    public var reasons: [String]

    public init(level: Mergeability, reasons: [String] = []) {
        self.level = level
        self.reasons = reasons
    }
}

/// How many signs of unreviewed, low-effort code ("slop") the change shows — whoever or whatever wrote it.
public enum SlopLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case none, some, many

    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// One sign of slop with the places that show it.
public struct SlopSign: Hashable, Sendable, Codable {
    public let title: String
    public let rationale: String
    public var evidence: [CodeLocationText]

    public init(title: String, rationale: String, evidence: [CodeLocationText] = []) {
        self.title = title
        self.rationale = rationale
        self.evidence = evidence
    }
}

/// Signs of slop: tells how much careful human review is worth before the author cleans up.
public struct SlopAssessment: Hashable, Sendable, Codable {
    public var level: SlopLevel
    public var signs: [SlopSign]

    public init(level: SlopLevel, signs: [SlopSign] = []) {
        self.level = level
        self.signs = signs
    }

    /// Worth sending the findings back to the author before reviewing in depth.
    public var suggestsSendingBack: Bool { level == .many }
}

/// Whether a change is worth remembering — for the team's knowledge of the system, independent of its risk.
/// Only two kinds count: domain knowledge and fundamental technical changes (`TakeawayKind`).
public enum KnowledgeLevel: String, Codable, Sendable, CaseIterable, Comparable {
    // Least first: with several shards or models the highest rating wins.
    /// Nothing to remember, however risky: cleanups, fixes without new rules, upkeep, tests only.
    case routine
    /// A small detail of the domain or the technical foundation (a default, a limit, an edge case).
    case minor
    /// New or changed domain knowledge (business rules, logic) or a fundamental technical change.
    case notable

    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// What kind of knowledge a takeaway is.
public enum TakeawayKind: String, Codable, Sendable, CaseIterable {
    /// What the system does for the business: rules, logic, calculations, processes, terms.
    case domain
    /// How the system is built: architecture, patterns, data model, interfaces, security, operations.
    case technical
}

/// One thing to remember about a change, one plain sentence.
public struct Takeaway: Hashable, Sendable, Codable, ExpressibleByStringLiteral {
    /// `nil` for reviews from before the kinds.
    public var kind: TakeawayKind?
    public var text: String

    public init(_ text: String, kind: TakeawayKind? = nil) {
        self.text = text
        self.kind = kind
    }

    public init(stringLiteral value: String) {
        self.init(value)
    }

    /// Reads `{"kind","text"}` and — from older reviews and agents — a plain string.
    public init(from decoder: any Decoder) throws {
        if let text = try? decoder.singleValueContainer().decode(String.self) {
            self.init(text)
            return
        }
        let container = try decoder.container(keyedBy: CodingKeys.self)
        self.init(
            try container.decode(String.self, forKey: .text),
            kind: try? container.decodeIfPresent(TakeawayKind.self, forKey: .kind))
    }
}

/// Whether to remember the change, and what exactly: the takeaways someone who didn't review it should know.
public struct KnowledgeAssessment: Hashable, Sendable, Codable {
    public var level: KnowledgeLevel
    /// What to remember, one sentence each (empty for routine changes).
    public var takeaways: [Takeaway]

    public init(level: KnowledgeLevel, takeaways: [Takeaway] = []) {
        self.level = level
        self.takeaways = takeaways
    }
}
