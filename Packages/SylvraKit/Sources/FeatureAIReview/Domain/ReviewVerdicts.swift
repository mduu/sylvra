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
