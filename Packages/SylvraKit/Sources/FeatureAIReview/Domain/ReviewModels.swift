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

/// One AI finding anchored to code (see specs/architecture.md §8.4).
public struct ReviewFinding: Identifiable, Hashable, Sendable {
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
    public var sources: [AgentSource]
    /// `false` when the location could not be matched to the diff.
    public var isAnchored: Bool

    public init(
        id: UUID = UUID(), path: String, startLine: Int, endLine: Int, severity: FindingSeverity, category: String,
        title: String, rationale: String, suggestion: String? = nil, confidence: Double = 0.5,
        sources: [AgentSource] = [], isAnchored: Bool = true
    ) {
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
public struct CodeLocationText: Hashable, Sendable, CustomStringConvertible {
    public let path: String
    public let startLine: Int
    public let endLine: Int
    public var description: String {
        let name = (path as NSString).lastPathComponent
        return startLine == endLine ? "\(name):\(startLine)" : "\(name):\(startLine)–\(endLine)"
    }
}

/// "What patterns are used or missed?" (see specs/projectidea.md §5.7).
public struct PatternFinding: Identifiable, Hashable, Sendable {
    public enum Verdict: String, Codable, Sendable {
        case followed, violated, introduced
    }

    public var id: String { name + verdict.rawValue }
    public let name: String
    public let verdict: Verdict
    public let rationale: String
    public let evidence: [CodeLocationText]
}

/// Merged result of a review run.
public struct ReviewResult: Hashable, Sendable {
    public var summary: String
    public var findings: [ReviewFinding]
    public var patterns: [PatternFinding]
    public var history: [String]

    public init(
        summary: String = "", findings: [ReviewFinding] = [], patterns: [PatternFinding] = [], history: [String] = []
    ) {
        self.summary = summary
        self.findings = findings
        self.patterns = patterns
        self.history = history
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
