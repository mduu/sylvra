import Foundation
import SylvraCore

/// Which agent, model and effort produced something (see specs/architecture.md §8.2).
public struct AgentSource: Hashable, Sendable, Codable {
    public let provider: String
    public let model: String
    public let effort: String

    public init(provider: String, model: String, effort: String) {
        self.provider = provider
        self.model = model
        self.effort = effort
    }
}

public enum FindingSeverity: String, Codable, Sendable, CaseIterable, Comparable {
    case critical, major, minor, nit

    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// A coarse risk rating (merge risk of a pull request, impact or likelihood of a finding).
public enum RiskLevel: String, Codable, Sendable, CaseIterable, Comparable {
    case low, medium, high

    var rank: Int { Self.allCases.firstIndex(of: self) ?? 0 }
    public static func < (lhs: Self, rhs: Self) -> Bool { lhs.rank < rhs.rank }
}

/// How risky merging the pull request is, with the main reasons.
public struct RiskAssessment: Hashable, Sendable, Codable {
    public var level: RiskLevel
    public var reasons: [String]

    public init(level: RiskLevel, reasons: [String] = []) {
        self.level = level
        self.reasons = reasons
    }
}

/// One AI finding anchored to code (see specs/architecture.md §8.4).
public struct ReviewFinding: Identifiable, Hashable, Sendable, Codable {
    public let id: UUID
    public let path: String
    public let startLine: Int
    public let endLine: Int
    public let severity: FindingSeverity
    public let category: String
    public let title: String
    public let rationale: String
    public let suggestion: String?
    public let confidence: Double
    /// How bad it is if the problem occurs (`nil` for reviews from before risk ratings).
    public var impact: RiskLevel?
    /// How likely the problem occurs in practice.
    public var likelihood: RiskLevel?
    public var sources: [AgentSource]
    /// `false` when the location could not be matched to the diff.
    public var isAnchored: Bool

    public init(
        id: UUID = UUID(), path: String, startLine: Int, endLine: Int, severity: FindingSeverity, category: String,
        title: String, rationale: String, suggestion: String? = nil, confidence: Double = 0.5,
        impact: RiskLevel? = nil, likelihood: RiskLevel? = nil, sources: [AgentSource] = [], isAnchored: Bool = true
    ) {
        self.impact = impact
        self.likelihood = likelihood
        self.id = id
        self.path = path
        self.startLine = startLine
        self.endLine = max(endLine, startLine)
        self.severity = severity
        self.category = category
        self.title = title
        self.rationale = rationale
        self.suggestion = suggestion
        self.confidence = confidence
        self.sources = sources
        self.isAnchored = isAnchored
    }

    public var location: CodeLocationText { CodeLocationText(path: path, startLine: startLine, endLine: endLine) }
}

/// "path:line" style location for display.
public struct CodeLocationText: Hashable, Sendable, CustomStringConvertible, Codable {
    public let path: String
    public let startLine: Int
    public let endLine: Int
    public var description: String {
        let name = (path as NSString).lastPathComponent
        return startLine == endLine ? "\(name):\(startLine)" : "\(name):\(startLine)–\(endLine)"
    }
}

/// "What patterns are used or missed?" (see specs/projectidea.md §5.7).
public struct PatternFinding: Identifiable, Hashable, Sendable, Codable {
    public enum Verdict: String, Codable, Sendable {
        case followed, violated, introduced
    }

    public var id: String { name + verdict.rawValue }
    public let name: String
    public let verdict: Verdict
    public let rationale: String
    public let evidence: [CodeLocationText]
}

/// A point about the pull request as a whole: could be more compact, too much code, too scattered.
public struct OverallFinding: Identifiable, Hashable, Sendable, Codable {
    public enum Kind: String, Codable, Sendable {
        case simpler, tooMuchCode, scattered, other
    }

    public var id: String { title }
    public let kind: Kind
    public let title: String
    public let rationale: String
}

/// What the reviewers say about one of the author's hints (a point to pay particular attention to).
public struct HintAnswer: Hashable, Sendable, Codable {
    public struct Answer: Hashable, Sendable, Codable {
        public let model: String
        public let text: String

        public init(model: String, text: String) {
            self.model = model
            self.text = text
        }
    }

    public let hint: String
    /// One per agent that answered (models, and shards of a large change).
    public var answers: [Answer]

    public init(hint: String, answers: [Answer] = []) {
        self.hint = hint
        self.answers = answers
    }
}

/// Merged result of a review run.
public struct ReviewResult: Hashable, Sendable, Codable {
    public var summary: String
    public var findings: [ReviewFinding]
    public var patterns: [PatternFinding]
    /// Points about the pull request as a whole (empty for reviews from before they were asked for).
    public var overall: [OverallFinding] = []
    public var history: [String]
    /// Suggested reading order (core and risky files first).
    public var readingOrder: [ReadingStep]
    /// The pull request's head commit the review saw (`nil` for reviews cached before this was recorded).
    public var headSHA: String?
    /// When the review finished.
    public var reviewedAt: Date?
    /// How risky merging the pull request is (`nil` for reviews from before risk ratings).
    public var risk: RiskAssessment?
    /// Whether it can be merged as it is (`nil` for older reviews).
    public var mergeability: MergeabilityAssessment?
    /// Signs of unreviewed, low-effort code (`nil` for older reviews).
    public var slop: SlopAssessment?
    /// Whether the change is worth remembering, and what (`nil` for older reviews).
    public var knowledge: KnowledgeAssessment?
    /// Answers to the author's hints, in the order given (empty without hints).
    public var hints: [HintAnswer] = []
    /// How long the review took, from start to result (`nil` for older reviews).
    public var duration: TimeInterval?
    /// Tokens its agents used (`nil`: unknown).
    public var tokens: TokenUsage?

    public init(
        summary: String = "", findings: [ReviewFinding] = [], patterns: [PatternFinding] = [], history: [String] = [],
        readingOrder: [ReadingStep] = [], risk: RiskAssessment? = nil
    ) {
        self.risk = risk
        self.summary = summary
        self.findings = findings
        self.patterns = patterns
        self.history = history
        self.readingOrder = readingOrder
    }

    private enum CodingKeys: String, CodingKey {
        case summary, findings, patterns, overall, history, readingOrder, headSHA, reviewedAt, risk, hints
        case duration, tokens, mergeability, slop, knowledge
    }

    // Results cached before reading orders (or head commits) were recorded decode without them.
    public init(from decoder: any Decoder) throws {
        let container = try decoder.container(keyedBy: CodingKeys.self)
        summary = try container.decode(String.self, forKey: .summary)
        findings = try container.decode([ReviewFinding].self, forKey: .findings)
        patterns = try container.decode([PatternFinding].self, forKey: .patterns)
        overall = try container.decodeIfPresent([OverallFinding].self, forKey: .overall) ?? []
        history = try container.decode([String].self, forKey: .history)
        readingOrder = try container.decodeIfPresent([ReadingStep].self, forKey: .readingOrder) ?? []
        headSHA = try container.decodeIfPresent(String.self, forKey: .headSHA)
        reviewedAt = try container.decodeIfPresent(Date.self, forKey: .reviewedAt)
        risk = try container.decodeIfPresent(RiskAssessment.self, forKey: .risk)
        mergeability = try container.decodeIfPresent(MergeabilityAssessment.self, forKey: .mergeability)
        slop = try container.decodeIfPresent(SlopAssessment.self, forKey: .slop)
        knowledge = try container.decodeIfPresent(KnowledgeAssessment.self, forKey: .knowledge)
        hints = try container.decodeIfPresent([HintAnswer].self, forKey: .hints) ?? []
        duration = try container.decodeIfPresent(TimeInterval.self, forKey: .duration)
        tokens = try container.decodeIfPresent(TokenUsage.self, forKey: .tokens)
    }
}

/// A file the agent should review, with the lines changed on the new side.
public struct ReviewableFile: Hashable, Sendable {
    public let path: String
    public let patch: String
    public let changedNewLines: Set<Int>
    /// Lines visible in the diff (added + context) — findings may anchor here.
    public let visibleNewLines: Set<Int>
    public let isNoise: Bool

    public init(path: String, patch: String, changedNewLines: Set<Int>, visibleNewLines: Set<Int>, isNoise: Bool) {
        self.path = path
        self.patch = patch
        self.changedNewLines = changedNewLines
        self.visibleNewLines = visibleNewLines
        self.isNoise = isNoise
    }

    var weight: Int { max(changedNewLines.count, 1) + patch.count / 400 }
    var directory: String { (path as NSString).deletingLastPathComponent }
}

/// User-facing review settings (defaults in settings, override per PR).
public struct ReviewSettings: Hashable, Sendable, Codable {
    /// English name of the user's preferred language, e.g. "German".
    public static var systemLanguageName: String {
        let code = Locale.preferredLanguages.first.map {
            Locale(identifier: $0).language.languageCode?.identifier ?? "en"
        }
        return Locale(identifier: "en").localizedString(forLanguageCode: code ?? "en") ?? "English"
    }

    public var models: [String]
    public var effort: String
    public var maxParallelAgents: Int
    /// PRs with fewer changed lines use a single agent.
    public var shardThreshold: Int
    /// Language for summaries, rationales and chat (e.g. "German").
    public var agentLanguage: String

    public init(
        models: [String] = ["opus"], effort: String = "high", maxParallelAgents: Int = 3, shardThreshold: Int = 400,
        agentLanguage: String = ReviewSettings.systemLanguageName
    ) {
        self.models = models
        self.effort = effort
        self.maxParallelAgents = maxParallelAgents
        self.shardThreshold = shardThreshold
        self.agentLanguage = agentLanguage
    }
}
