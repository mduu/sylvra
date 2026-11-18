import Foundation

/// Everything an agent needs for one shard (see specs/architecture.md §8.3).
public struct ReviewRequest: Sendable {
    public let pullRequestTitle: String
    public let pullRequestBody: String
    public let shard: ShardPlanner.Shard
    public let repositoryContext: [ContextDocument]
    public let history: [String]
    public let model: String
    public let effort: String
    public let language: String
    /// Checked-out code the agent may read (worktree), if available.
    public let workingDirectory: URL?

    public init(
        pullRequestTitle: String, pullRequestBody: String, shard: ShardPlanner.Shard,
        repositoryContext: [ContextDocument],
        history: [String], model: String, effort: String, language: String, workingDirectory: URL?
    ) {
        self.pullRequestTitle = pullRequestTitle
        self.pullRequestBody = pullRequestBody
        self.shard = shard
        self.repositoryContext = repositoryContext
        self.history = history
        self.model = model
        self.effort = effort
        self.language = language
        self.workingDirectory = workingDirectory
    }

    /// The prompt sent on standard input.
    public var prompt: String {
        var parts: [String] = []
        parts.append(
            """
            You are reviewing a GitHub pull request as an experienced senior engineer. Review ONLY the files of this \
            shard (\(shard.name)). Focus on correctness, security, concurrency, performance, design and missing tests. \
            Be precise and concise; prefer few, important findings over many trivial ones. Do not invent problems.

            Also answer "What patterns are used or missed?": name the architectural and code patterns the change \
            follows, violates or newly introduces, especially rules documented in the repository guidelines below.

            Line numbers refer to the NEW version of the file (right side of the diff). Only report findings on lines \
            that appear in the diff. A `suggestion` is applied 1:1 as a GitHub suggestion: it must be the complete \
            replacement code for exactly startLine…endLine, with the original indentation, and nothing else — no \
            prose, no placeholders such as "…", no code for other lines. When the fix is not such a replacement, \
            omit `suggestion` and describe the fix in the rationale.

            Also suggest a reading order (`readingOrder`): the changed files of this shard in the order a reviewer \
            should read them — the core change and risky areas first, then what depends on it, tests and mechanical \
            changes last. Give each a short reason (a few words) and mark risky areas with `risky: true`.

            Rate the risk of merging this change (`risk`): `level` low, medium or high, and one to three short \
            `reasons` naming what could break and for whom. For every finding, rate `impact` (how bad it is if it \
            happens) and `likelihood` (how likely it happens in practice), each low, medium or high.

            Write summary, titles, rationales, risk reasons, reading-order reasons and pattern explanations in \
            \(language). Keep code, identifiers and \
            suggestions unchanged.
            """)
        parts.append("## Pull request\n\nTitle: \(pullRequestTitle)\n\n\(pullRequestBody.prefix(4000))")
        if !repositoryContext.isEmpty {
            let documents = repositoryContext.map { "### \($0.path)\n\n\($0.content)" }.joined(separator: "\n\n")
            parts.append("## Repository guidelines (AGENTS.md, CLAUDE.md, specs, …)\n\n\(documents)")
        }
        if !history.isEmpty {
            parts.append("## Earlier changes to the same files\n\n" + history.joined(separator: "\n"))
        }
        let patches = shard.files.map { "### \($0.path)\n\n```diff\n\($0.patch)\n```" }.joined(separator: "\n\n")
        parts.append("## Diff of this shard\n\n\(patches)")
        if workingDirectory != nil {
            parts.append("You may read other files of the repository (read-only) when you need more context.")
        }
        return parts.joined(separator: "\n\n")
    }

    /// JSON schema of the structured output.
    public static let outputSchema = """
        {"type":"object","required":["summary","risk","findings","patterns"],"properties":{\
        "summary":{"type":"string"},\
        "risk":{"type":"object","required":["level","reasons"],"properties":{\
        "level":{"type":"string","enum":["low","medium","high"]},"reasons":{"type":"array","items":{"type":"string"}}}},\
        "findings":{"type":"array","items":{"type":"object",\
        "required":["path","startLine","endLine","severity","category","title","rationale","confidence","impact",\
        "likelihood"],"properties":{\
        "path":{"type":"string"},"startLine":{"type":"integer"},"endLine":{"type":"integer"},\
        "severity":{"type":"string","enum":["critical","major","minor","nit"]},\
        "category":{"type":"string","enum":["bug","security","performance","concurrency","design","tests","style","pattern"]},\
        "title":{"type":"string"},"rationale":{"type":"string"},"suggestion":{"type":"string"},\
        "confidence":{"type":"number"},"impact":{"type":"string","enum":["low","medium","high"]},\
        "likelihood":{"type":"string","enum":["low","medium","high"]}}}},\
        "patterns":{"type":"array","items":{"type":"object","required":["name","verdict","rationale"],"properties":{\
        "name":{"type":"string"},"verdict":{"type":"string","enum":["followed","violated","introduced"]},\
        "rationale":{"type":"string"},"evidence":{"type":"array","items":{"type":"object",\
        "properties":{"path":{"type":"string"},"startLine":{"type":"integer"},"endLine":{"type":"integer"}}}}}}},\
        "readingOrder":{"type":"array","items":{"type":"object","required":["path","reason"],"properties":{\
        "path":{"type":"string"},"reason":{"type":"string"},"risky":{"type":"boolean"}}}},\
        "history":{"type":"array","items":{"type":"string"}}}}
        """
}

/// A repository document passed as context.
public struct ContextDocument: Hashable, Sendable {
    public let path: String
    public let content: String

    public init(path: String, content: String) {
        self.path = path
        self.content = content
    }
}

/// Raw structured output of one agent run.
public struct AgentReviewOutput: Decodable, Sendable {
    public struct Finding: Decodable, Sendable {
        let path: String
        let startLine: Int
        let endLine: Int?
        let severity: FindingSeverity
        let category: String?
        let title: String
        let rationale: String?
        let suggestion: String?
        let confidence: Double?
        let impact: RiskLevel?
        let likelihood: RiskLevel?
    }

    public struct Risk: Decodable, Sendable {
        let level: RiskLevel
        let reasons: [String]?
    }

    public struct Pattern: Decodable, Sendable {
        let name: String
        let verdict: PatternFinding.Verdict
        let rationale: String?
        let evidence: [Evidence]?
    }

    public struct Evidence: Decodable, Sendable {
        let path: String?
        let startLine: Int?
        let endLine: Int?
    }

    public struct Step: Decodable, Sendable {
        let path: String
        let reason: String?
        let risky: Bool?
    }

    let summary: String
    let risk: Risk?
    let readingOrder: [Step]?
    let findings: [Finding]
    let patterns: [Pattern]?
    let history: [String]?
}
