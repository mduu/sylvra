import Foundation

// MARK: - Submit

extension ReviewScreenModel {
    /// Submits the pending review (or a review without inline comments) and reloads the threads.
    public func submitReview() async {
        guard let nodeID = snapshot?.pullRequestNodeID, submitProblem == nil else { return }
        submitError = nil
        let reviewID = snapshot?.pendingReviewID
        let started = pullRequestID
        defer {
            if isSubmitSheetPresented, let errorMessage {
                submitError = errorMessage
                self.errorMessage = nil
            }
        }
        await perform("submit review") {
            try await self.service.submitReview(
                pullRequestNodeID: nodeID, reviewID: reviewID, event: self.submitEvent, body: self.submitBody)
            guard self.pullRequestID == started else { return }
            self.snapshot?.pendingReviewID = nil
            self.submitBody = ""
            self.submitEvent = .comment
            self.isSubmitSheetPresented = false
            try await self.reload()
        }
    }

    /// Why GitHub would refuse the review as it stands (`nil`: it can be submitted).
    public var submitProblem: String? {
        Self.submitProblem(
            event: submitEvent, body: submitBody, pendingCount: pendingCount,
            viewerDidAuthor: snapshot?.viewerDidAuthor ?? false)
    }

    /// GitHub's rules: no approval or change request on one's own pull request, a change request needs a summary,
    /// a comment needs a summary or inline comments.
    nonisolated static func submitProblem(
        event: ReviewEvent, body: String, pendingCount: Int, viewerDidAuthor: Bool
    ) -> String? {
        let hasBody = !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        switch event {
        case .approve:
            return viewerDidAuthor ? String(localized: "You can't approve your own pull request.") : nil
        case .requestChanges:
            if viewerDidAuthor { return String(localized: "You can't request changes on your own pull request.") }
            return hasBody ? nil : String(localized: "Requesting changes needs a summary: say what has to change.")
        case .comment:
            return hasBody || pendingCount > 0
                ? nil : String(localized: "Write a summary or add inline comments to submit a comment.")
        }
    }
}
