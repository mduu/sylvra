import Foundation

/// The prompt, answer schema and decoding for checking one stage of a delivery.
public enum VerificationPrompt {
    /// Read-only GitHub commands the agent may run on top of what the user allowed in their own agent setup.
    public static let allowedTools = [
        "Bash(gh run view:*)", "Bash(gh run list:*)", "Bash(gh pr view:*)", "Bash(gh pr diff:*)",
        "Bash(gh pr checks:*)", "Bash(gh workflow view:*)", "Bash(gh release view:*)", "Bash(git log:*)",
        "Bash(git show:*)", "Bash(git diff:*)",
    ]

    public static func prompt(for request: VerificationRequest, now: Date = .now) -> String {
        let stage = request.stage
        let id = request.pullRequest
        let time = ISO8601DateFormatter()
        var lines = [
            "A pull request was merged and is being delivered. Check the stage \"\(stage.name)\" of its delivery.",
            "",
            "Pull request: \(id.owner)/\(id.repository) #\(id.number) — \(request.title)",
            "Merge commit: \(request.delivery.mergeCommitSHA)"
                + (request.delivery.mergedAt.map { ", merged \(time.string(from: $0))" } ?? ""),
            "Now: \(time.string(from: now))",
            "Stages (from GitHub): "
                + request.delivery.stages.map { "\($0.name) [\($0.state.rawValue)]" }.joined(separator: " → "),
            "",
            "Stage \"\(stage.name)\" (\(stage.kind == .environment ? "deployment to an environment" : "build")): "
                + stage.state.rawValue
                + (stage.startedAt.map { ", started \(time.string(from: $0))" } ?? "")
                + (stage.finishedAt.map { ", finished \(time.string(from: $0))" } ?? ""),
        ]
        if let url = stage.url { lines.append("Workflow run or deployment: \(url.absoluteString)") }
        for job in stage.jobs {
            var line = "- job \"\(job.name)\": \(job.state.rawValue)"
            if !job.failedSteps.isEmpty { line += "; failed steps: " + job.failedSteps.joined(separator: ", ") }
            lines.append(line)
            lines += job.errors.map { "  reported: \($0.prefix(500))" }
        }
        lines += [
            "",
            "Pull request description:",
            request.body.isEmpty ? "(none)" : String(request.body.prefix(4_000)),
            "",
        ]
        if !request.monitoringNotes.isEmpty {
            lines += ["The user's notes on this repository's monitoring:", request.monitoringNotes, ""]
        }
        lines.append(task(for: request))
        return lines.joined(separator: "\n")
    }

    private static func task(for request: VerificationRequest) -> String {
        let stage = request.stage
        let common = """
            How to work:
            - Read the repository's AGENTS.md / CLAUDE.md (and what they point to) in the added directory: they \
            say which logging and monitoring tools this repository uses and how its services and environments \
            are named. Use those tools if they are available to you; `gh` (read-only commands) is available for \
            workflow runs and their logs (`gh run view <id> --log-failed`).
            - You only read. If a tool is missing or a call is denied, do not work around it: list the point \
            under `notChecked` with the reason (e.g. "Datadog tools are not allowed in Claude Code's settings").
            - First state in `intent` what the change is meant to fix or introduce (one or two sentences, from \
            the description and, if needed, the diff via `gh pr diff`).
            - Every check names its evidence: the tool, the query or command, the time window and the figures \
            (before and after the deployment where that makes sense). No evidence, no claim.
            - Do not check user interface behaviour or anything that leaves no trace in logs or metrics; list \
            such points under `notChecked`.
            - `verdict`: "problems" if the stage failed or the deployed change shows errors; "healthy" if it \
            deployed and what you could check shows no trouble; "unchecked" if you could check nothing \
            meaningful. Keep `summary` to one or two sentences.
            """
        if stage.state == .failed {
            return """
                The stage failed. Find out why: which step, what the log says, and whether this pull request's \
                change caused it or something unrelated (infrastructure, a flaky step, another change). Say \
                what to do next.

                \(common)
                """
        }
        let second =
            request.isSecondLook
            ? "This is a second look some time after the deployment: compare the time since the deployment "
                + "with the time before it, and look for what only shows under real traffic.\n"
            : ""
        return """
            \(second)Check, as far as the tools allow:
            1. Did the deployment to "\(stage.name)" really happen and finish (the deployed version or commit, \
            if the tools show it)?
            2. Does the deployed service throw new errors or more errors since the deployment than before \
            (logs, error tracking, monitors, alerts for this environment)?
            3. Does the change show the effect it was made for, if that leaves a trace in logs or metrics \
            (an error that should be gone, a new endpoint or job being called, a rate, a monitor)?

            \(common)
            """
    }

    public static let schema = """
        {"type":"object","required":["verdict","summary","intent","checks","notChecked"],"properties":{
        "verdict":{"type":"string","enum":["healthy","problems","unchecked"]},
        "summary":{"type":"string"},"intent":{"type":"string"},
        "checks":{"type":"array","items":{"type":"object","required":["title","outcome","finding"],"properties":{
        "title":{"type":"string"},"outcome":{"type":"string","enum":["ok","problem","unchecked"]},
        "finding":{"type":"string"},"evidence":{"type":"string"}}}},
        "notChecked":{"type":"array","items":{"type":"string"}}}}
        """

    struct Output: Decodable {
        let verdict: StageVerification.Verdict
        let summary: String
        let intent: String?
        let checks: [StageVerification.Check]?
        let notChecked: [String]?
    }

    /// The agent's answer as the verification of `request`'s stage.
    public static func decode(_ json: Data, for request: VerificationRequest, now: Date = .now) throws
        -> StageVerification
    {
        let output = try JSONDecoder().decode(Output.self, from: json)
        return StageVerification(
            stageID: request.stage.id, stageName: request.stage.name, verdict: output.verdict,
            summary: output.summary.trimmingCharacters(in: .whitespacesAndNewlines), intent: output.intent ?? "",
            checks: output.checks ?? [], notChecked: output.notChecked ?? [], checkedAt: now,
            isSecondLook: request.isSecondLook)
    }
}
