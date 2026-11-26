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
    /// The pull request's files outside this shard (`path (+added −removed)`), to judge the change as a whole.
    public var otherFiles: [String] = []
    /// Points the author asks the reviewers to pay particular attention to (on top of the usual review).
    public var hints: [String] = []

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

            Code comments: report comments that restate what the code already says or are longer than needed \
            (category `style`, severity `nit` or `minor`, a `suggestion` that removes or shortens them). A comment \
            belongs only where the intent or reason is not evident from the code, and then as short as possible.

            Also judge the pull request as a whole, not line by line (`overall`): could it be implemented much more \
            compactly or simply? Is it too much code for what it does (duplication, speculative abstractions, \
            unused flexibility)? Is it scattered over more places than needed, or does it belong in fewer files or \
            modules? Report only clear, substantial points — an empty list is fine. Give each a `kind` (`simpler`, \
            `tooMuchCode`, `scattered` or `other`), a short `title` and a `rationale` naming the files concerned.

            Also answer "What patterns are used or missed?": name the architectural and code patterns the change \
            follows, violates or newly introduces, especially rules documented in the repository guidelines below. \
            Every pattern needs `evidence`: one to three places on lines of the diff (path, startLine, endLine) that \
            show it.

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

            Judge whether this change can be merged as it is (`mergeability`), independent of its risk — a risky \
            change can be excellent: `level` excellent (clean, well tested, nothing to change), good (only minor \
            points), acceptable (works, but should be improved; fine to merge with follow-ups) or notMergeable \
            (must not be merged as is: bugs, security problems, missing essential tests or a wrong approach), and \
            one to three short `reasons`; for notMergeable name the blockers.

            Rate the signs of unreviewed, low-effort code (`slop`), whoever or whatever wrote it — do not guess \
            whether an AI wrote it. This tells the reviewer how much careful human review is worth before the author \
            cleans up. Typical signs: comments that restate the code, verbose docs, speculative abstractions, \
            defensive checks for impossible cases, dead or duplicated code, made-up or misused APIs, code that \
            ignores the repository's conventions, tests that test nothing (mocks testing mocks, assertions that \
            always pass), a description that doesn't match the diff, unrelated changes. `level` none, some or many, \
            and `signs`: only clear ones, each with a short `title`, a `rationale` and one to three places on lines \
            of the diff as `evidence`. An empty list with none is fine.

            Judge whether this change is worth remembering for the people who work on the system (`knowledge`), \
            independent of its risk: `level` notable (changes how the system behaves or is used — logic, business \
            rules, contracts and APIs, data and schemas, configuration, permissions, operations), minor (a small \
            detail worth knowing, such as a changed default, limit or message) or routine (nothing to remember: \
            cleanups, formatting, renames without effect, dependency bumps, tests only). For notable and minor give \
            one to three `takeaways`: what someone who did not review it should know afterwards, one plain sentence \
            each ("Invoices now round VAT per invoice, not per line."); none for routine.

            Keep the `summary` short and to the point: two or three sentences on what the change does and why, \
            and what matters most for merging it (the main risk or the biggest problem). Leave out file lists, \
            details the findings already carry, and praise — but nothing essential.

            Write summary, titles, rationales, risk and mergeability reasons, slop signs, knowledge takeaways, \
            reading-order reasons, \
            overall points and pattern explanations in \
            \(language). Keep code, identifiers and \
            suggestions unchanged.
            """)
        parts.append("## Pull request\n\nTitle: \(pullRequestTitle)\n\n\(pullRequestBody.prefix(4000))")
        if !hints.isEmpty { parts.append(Self.hintsSection(hints)) }
        if !repositoryContext.isEmpty {
            let documents = repositoryContext.map { "### \($0.path)\n\n\($0.content)" }.joined(separator: "\n\n")
            parts.append("## Repository guidelines (AGENTS.md, CLAUDE.md, specs, …)\n\n\(documents)")
        }
        if !history.isEmpty {
            parts.append("## Earlier changes to the same files\n\n" + history.joined(separator: "\n"))
        }
        if !otherFiles.isEmpty {
            parts.append(
                "## Other files of this pull request (reviewed separately; for judging the change as a whole)\n\n"
                    + otherFiles.map { "- \($0)" }.joined(separator: "\n"))
        }
        let patches = shard.files.map { "### \($0.path)\n\n```diff\n\($0.patch)\n```" }.joined(separator: "\n\n")
        parts.append("## Diff of this shard\n\n\(patches)")
        if workingDirectory != nil {
            parts.append("You may read other files of the repository (read-only) when you need more context.")
        }
        return parts.joined(separator: "\n\n")
    }

    /// The author's hints: an addition to the review, not a limit on it.
    static func hintsSection(_ hints: [String]) -> String {
        """
        ## Reviewer hints

        Review the whole change as usual — these points don't limit what you look at. In addition, the author \
        asks you to pay particular attention to them. Report problems you find about them as normal findings. \
        In `hints`, answer every point in one or two sentences in the review language: what you checked in this \
        shard and what you found, or that this shard doesn't touch it. Copy each `hint` exactly as written here.

        """ + hints.enumerated().map { "\($0.offset + 1). \($0.element)" }.joined(separator: "\n")
    }

    /// JSON schema of the structured output.
    public static let outputSchema = """
        {"type":"object","required":["summary","risk","mergeability","slop","knowledge","findings","overall","patterns"],"properties":{\
        "summary":{"type":"string"},\
        "risk":{"type":"object","required":["level","reasons"],"properties":{\
        "level":{"type":"string","enum":["low","medium","high"]},"reasons":{"type":"array","items":{"type":"string"}}}},\
        "mergeability":{"type":"object","required":["level","reasons"],"properties":{\
        "level":{"type":"string","enum":["excellent","good","acceptable","notMergeable"]},\
        "reasons":{"type":"array","items":{"type":"string"}}}},\
        "knowledge":{"type":"object","required":["level","takeaways"],"properties":{\
        "level":{"type":"string","enum":["notable","minor","routine"]},\
        "takeaways":{"type":"array","items":{"type":"string"}}}},\
        "slop":{"type":"object","required":["level","signs"],"properties":{\
        "level":{"type":"string","enum":["none","some","many"]},\
        "signs":{"type":"array","items":{"type":"object","required":["title","rationale","evidence"],"properties":{\
        "title":{"type":"string"},"rationale":{"type":"string"},"evidence":{"type":"array","items":{"type":"object",\
        "required":["path","startLine","endLine"],\
        "properties":{"path":{"type":"string"},"startLine":{"type":"integer"},"endLine":{"type":"integer"}}}}}}}}},\
        "findings":{"type":"array","items":{"type":"object",\
        "required":["path","startLine","endLine","severity","category","title","rationale","confidence","impact",\
        "likelihood"],"properties":{\
        "path":{"type":"string"},"startLine":{"type":"integer"},"endLine":{"type":"integer"},\
        "severity":{"type":"string","enum":["critical","major","minor","nit"]},\
        "category":{"type":"string","enum":["bug","security","performance","concurrency","design","tests","style","pattern"]},\
        "title":{"type":"string"},"rationale":{"type":"string"},"suggestion":{"type":"string"},\
        "confidence":{"type":"number"},"impact":{"type":"string","enum":["low","medium","high"]},\
        "likelihood":{"type":"string","enum":["low","medium","high"]}}}},\
        "overall":{"type":"array","items":{"type":"object","required":["kind","title","rationale"],"properties":{\
        "kind":{"type":"string","enum":["simpler","tooMuchCode","scattered","other"]},"title":{"type":"string"},\
        "rationale":{"type":"string"}}}},\
        "patterns":{"type":"array","items":{"type":"object","required":["name","verdict","rationale","evidence"],\
        "properties":{\
        "name":{"type":"string"},"verdict":{"type":"string","enum":["followed","violated","introduced"]},\
        "rationale":{"type":"string"},"evidence":{"type":"array","minItems":1,"items":{"type":"object",\
        "required":["path","startLine","endLine"],\
        "properties":{"path":{"type":"string"},"startLine":{"type":"integer"},"endLine":{"type":"integer"}}}}}}},\
        "readingOrder":{"type":"array","items":{"type":"object","required":["path","reason"],"properties":{\
        "path":{"type":"string"},"reason":{"type":"string"},"risky":{"type":"boolean"}}}},\
        "history":{"type":"array","items":{"type":"string"}},\
        "hints":{"type":"array","items":{"type":"object","required":["hint","answer"],"properties":{\
        "hint":{"type":"string"},"answer":{"type":"string"}}}}}}
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
    /// Tokens the agent used (set by the provider, not part of the agent's answer).
    public var tokens: TokenUsage?
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

    public struct MergeVerdict: Decodable, Sendable {
        let level: Mergeability
        let reasons: [String]?
    }

    public struct Knowledge: Decodable, Sendable {
        let level: KnowledgeLevel
        let takeaways: [String]?
    }

    public struct Slop: Decodable, Sendable {
        let level: SlopLevel
        let signs: [Sign]?
    }

    public struct Sign: Decodable, Sendable {
        let title: String
        let rationale: String?
        let evidence: [Evidence]?
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

    /// A point about the pull request as a whole (more compact, too much code, scattered).
    public struct Overall: Decodable, Sendable {
        let kind: String?
        let title: String
        let rationale: String?
    }

    /// An agent's answer to one of the author's hints.
    public struct Hint: Decodable, Sendable {
        let hint: String
        let answer: String
    }

    public struct Step: Decodable, Sendable {
        let path: String
        let reason: String?
        let risky: Bool?
    }

    let summary: String
    let risk: Risk?
    let mergeability: MergeVerdict?
    let slop: Slop?
    let knowledge: Knowledge?
    let readingOrder: [Step]?
    let findings: [Finding]
    let overall: [Overall]?
    let patterns: [Pattern]?
    let history: [String]?
    let hints: [Hint]?
}
