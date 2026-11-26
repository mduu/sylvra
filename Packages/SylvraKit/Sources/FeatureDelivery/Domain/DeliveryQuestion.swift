import Foundation

/// The question *Ask AI about this* sends for a stage: what GitHub reports, as text.
enum DeliveryQuestion {
    static func about(_ stage: DeliveryStage, of delivery: Delivery, verification: StageVerification? = nil)
        -> String
    {
        var lines = facts(stage, delivery, verification)
        lines.append(
            stage.state == .failed
                ? "What most likely went wrong, is it related to this pull request's change, and what should I do next?"
                : "What does this stage do for this change, and is there anything I should watch out for?")
        return lines.joined(separator: "\n")
    }

    /// The opening of an interactive session: the same facts, and the user decides what to do.
    static func session(about stage: DeliveryStage, of delivery: Delivery, verification: StageVerification?)
        -> String
    {
        var lines = [
            "Context from Sylvra: pull request \(delivery.pullRequest) (\(delivery.title)) is being delivered."
        ]
        lines += facts(stage, delivery, verification)
        lines.append("Wait for my instructions before changing anything.")
        return lines.joined(separator: "\n")
    }

    private static func facts(_ stage: DeliveryStage, _ delivery: Delivery, _ verification: StageVerification?)
        -> [String]
    {
        var lines = [
            "This pull request was merged (merge commit \(delivery.mergeCommitSHA.prefix(10))). "
                + "Its delivery stage \"\(stage.name)\" is: \(stage.state.rawValue).",
            "All stages: " + delivery.stages.map { "\($0.name) (\($0.state.rawValue))" }.joined(separator: " → "),
        ]
        for job in stage.jobs {
            var line = "- Job \"\(job.name)\": \(job.state.rawValue)"
            if !job.failedSteps.isEmpty { line += "; failed steps: " + job.failedSteps.joined(separator: ", ") }
            lines.append(line)
            lines += job.errors.map { "  error: \($0.prefix(400))" }
        }
        if let verification {
            lines.append("An AI check of this stage found: \(verification.verdict.rawValue) — \(verification.summary)")
            lines += verification.checks.map { "- \($0.title) [\($0.outcome.rawValue)]: \($0.finding)" }
            lines += verification.notChecked.map { "- not checked: \($0)" }
        }
        return lines
    }
}
