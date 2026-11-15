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
            that appear in the diff. A `suggestion` replaces exactly startLine…endLine.

            Write summary, titles, rationales and pattern explanations in \(language). Keep code, identifiers and \
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
        {"type":"object","required":["summary","findings","patterns"],"properties":{\
        "summary":{"type":"string"},\
        "findings":{"type":"array","items":{"type":"object",\
        "required":["path","startLine","endLine","severity","category","title","rationale","confidence"],"properties":{\
        "path":{"type":"string"},"startLine":{"type":"integer"},"endLine":{"type":"integer"},\
        "severity":{"type":"string","enum":["critical","major","minor","nit"]},\
        "category":{"type":"string","enum":["bug","security","performance","concurrency","design","tests","style","pattern"]},\
        "title":{"type":"string"},"rationale":{"type":"string"},"suggestion":{"type":"string"},\
        "confidence":{"type":"number"}}}},\
        "patterns":{"type":"array","items":{"type":"object","required":["name","verdict","rationale"],"properties":{\
        "name":{"type":"string"},"verdict":{"type":"string","enum":["followed","violated","introduced"]},\
        "rationale":{"type":"string"},"evidence":{"type":"array","items":{"type":"object",\
        "properties":{"path":{"type":"string"},"startLine":{"type":"integer"},"endLine":{"type":"integer"}}}}}}},\
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

    let summary: String
    let findings: [Finding]
    let patterns: [Pattern]?
    let history: [String]?
}
