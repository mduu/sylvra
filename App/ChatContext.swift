import FeatureAIReview
import FeaturePullRequest
import SylvraCore

/// Builds the PR context sent with the first chat message (bridges PR details and AI results).
enum ChatContext {
    static func describe(_ id: PullRequestID, detail: PullRequestDetail?, review: ReviewResult?) -> String {
        var parts = ["You are helping to review the GitHub pull request \(id)."]
        if let detail, detail.summary.id == id {
            parts.append("Title: \(detail.summary.title)")
            parts.append("Branch: \(detail.summary.headRefName) → \(detail.summary.baseRefName)")
            if !detail.body.isEmpty { parts.append("Description:\n\(detail.body.prefix(3000))") }
            parts.append("Commits:\n" + detail.commits.map { "- \($0.shortSHA) \($0.subject)" }.joined(separator: "\n"))
        }
        if let review {
            parts.append("AI review summary:\n\(review.summary)")
            let findings = review.findings.prefix(20).map {
                "- [\($0.severity.rawValue)] \($0.path):\($0.startLine) \($0.title)"
            }
            if !findings.isEmpty { parts.append("Findings:\n" + findings.joined(separator: "\n")) }
        }
        parts.append("The checked-out code of the pull request is in the working directory (read-only).")
        return parts.joined(separator: "\n\n")
    }
}
