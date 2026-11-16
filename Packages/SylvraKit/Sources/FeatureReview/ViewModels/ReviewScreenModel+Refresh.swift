import Foundation
import SylvraCore

extension ReviewScreenModel {
    /// How often the open pull request's threads are reloaded (replies by others show up on their own).
    public static let threadRefreshInterval: Duration = .seconds(60)

    /// Reloads the threads now and then while the pull request is open. Ends when the task is cancelled.
    public func keepRefreshingThreads(every interval: Duration = threadRefreshInterval) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await refreshThreads()
        }
    }

    /// Loads the threads again and only touches the state when something changed — an unchanged answer
    /// must not re-render the diff or move its scroll position. Skipped while a write is in flight.
    public func refreshThreads() async {
        guard let id = pullRequestID, !isWorking, loadState == .loaded else { return }
        guard let loaded = try? await service.loadReview(for: id), !Task.isCancelled, pullRequestID == id,
            !isWorking
        else { return }
        if snapshot != loaded { snapshot = loaded }
    }
}

extension ReviewScreenModel {
    /// The question for "Ask AI" on a thread: the discussion so far, and a reply suggestion in the comment
    /// language after a fixed marker (so "Use as reply" can take just that part).
    public func aiQuestion(about thread: ReviewThread) -> String {
        let discussion = thread.comments.map { "@\($0.author.login): \($0.body)" }.joined(separator: "\n\n")
        return """
            This is a review discussion on the selected code:

            \(discussion)

            What do you think of the latest reply? Is it right, does it address the concern, and is anything \
            missing? Be brief and factual. If a reply from me is useful, end with a line "\(Self.suggestedReplyMarker)" \
            followed by a short, friendly reply in \(draftLanguage) (at most three sentences).
            """
    }

    public nonisolated static let suggestedReplyMarker = "Suggested reply:"

    /// The suggested reply of an AI answer to `aiQuestion(about:)`, or the whole answer without a marker.
    public nonisolated static func suggestedReply(in answer: String) -> String {
        guard let range = answer.range(of: suggestedReplyMarker, options: .backwards) else {
            return answer.trimmingCharacters(in: .whitespacesAndNewlines)
        }
        return answer[range.upperBound...].trimmingCharacters(in: .whitespacesAndNewlines)
            .trimmingCharacters(in: CharacterSet(charactersIn: "\"“”"))
    }

    /// Puts text into a thread's reply field (e.g. an AI suggestion the reviewer then edits).
    public func setReplyDraft(_ text: String, for threadID: String) {
        replyDrafts[threadID] = text
        if let thread = threads.first(where: { $0.id == threadID }), isCollapsed(thread) { toggleCollapsed(thread) }
    }
}

extension ReviewScreenModel {
    /// Comments of the viewer's pending review, with their threads.
    public var pendingComments: [(thread: ReviewThread, comment: ReviewComment)] {
        threads.flatMap { thread in thread.comments.filter(\.isPending).map { (thread, $0) } }
    }

    public var pendingCount: Int { threads.reduce(0) { $0 + $1.comments.count(where: \.isPending) } }
}
