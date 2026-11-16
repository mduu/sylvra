import Foundation
import SylvraCore

extension DetailNode {
    /// Conversation comments, non-empty review texts and code threads (first comment plus replies).
    var discussion: [DiscussionItem] {
        func user(_ node: CommentNode) -> UserRef { node.author?.userRef ?? UserRef(login: "ghost") }
        let general = (comments?.values ?? []).enumerated().map { index, node in
            DiscussionItem(
                id: node.id ?? "comment-\(index)", place: .conversation, author: user(node), body: node.body,
                date: node.date, url: node.url)
        }
        let reviewTexts = (reviews?.values ?? []).enumerated().compactMap { index, node -> DiscussionItem? in
            guard !node.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty else { return nil }
            return DiscussionItem(
                id: node.id ?? "review-\(index)", place: .review, author: user(node), body: node.body,
                date: node.date, url: node.url)
        }
        let threads = (reviewThreads?.values ?? []).enumerated().compactMap { index, thread -> DiscussionItem? in
            guard let first = thread.comments.values.first else { return nil }
            return DiscussionItem(
                id: thread.id ?? "thread-\(index)",
                place: .code(path: thread.path, line: thread.line, isResolved: thread.isResolved ?? false),
                author: user(first), body: first.body, date: first.date, url: first.url,
                replies: thread.comments.values.dropFirst().map {
                    DiscussionItem.Reply(author: user($0), body: $0.body, date: $0.date)
                })
        }
        return general + reviewTexts + threads
    }
}
