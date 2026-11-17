import Foundation
import SylvraCore

/// Fixture conversation for `--demo`, previews and tests. Writes only change local state.
public actor DemoConversationService: ConversationService {
    private var conversation: Conversation
    private var nextID = 1

    public init(conversation: Conversation = DemoConversationService.sample()) {
        self.conversation = conversation
    }

    public func loadConversation(for id: PullRequestID) async throws -> Conversation { conversation }

    public func addComment(pullRequestNodeID: String, body: String) async throws -> ConversationEntry {
        defer { nextID += 1 }
        let entry = ConversationEntry(
            kind: .comment,
            comment: ReviewComment(
                id: "demo-conversation-\(nextID)", author: DemoReviewService.viewer, body: body, createdAt: .now,
                viewerCanUpdate: true, viewerCanDelete: true))
        conversation.entries.append(entry)
        return entry
    }

    public func updateBody(of entry: ConversationEntry, to body: String) async throws -> String {
        guard let index = conversation.entries.firstIndex(where: { $0.id == entry.id }) else {
            throw DemoReviewError.notFound
        }
        conversation.entries[index].comment.body = body
        return body
    }

    public func deleteComment(id: String) async throws {
        conversation.entries.removeAll { $0.id == id }
    }

    public func setReaction(_ reaction: Reaction, added: Bool, subjectID: String) async throws {
        guard let index = conversation.entries.firstIndex(where: { $0.id == subjectID }) else {
            throw DemoReviewError.notFound
        }
        let current = conversation.entries[index].comment.reactions
        let reacted = current.first { $0.reaction == reaction }?.viewerHasReacted ?? false
        if reacted != added { conversation.entries[index].comment.reactions = current.toggling(reaction) }
    }

    // MARK: - Fixtures

    public static func sample(now: Date = .now) -> Conversation {
        let lena = UserRef(login: "lkeller", name: "Lena Keller")
        let jonas = UserRef(login: "jmeier", name: "Jonas Meier")
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        let url = URL(string: "https://github.com/acme/billing/pull/1234")
        return Conversation(
            pullRequestNodeID: "demo",
            entries: [
                ConversationEntry(
                    kind: .comment,
                    comment: ReviewComment(
                        id: "demo-conversation-lena", author: lena,
                        body: "Ready for review. The per-line rounding follows **BILL-311** — happy to change it "
                            + "if accounting agrees.",
                        createdAt: ago(26), url: url,
                        reactions: [
                            ReactionGroup(reaction: .thumbsUp, count: 1), ReactionGroup(reaction: .eyes, count: 1),
                        ]
                    )),
                ConversationEntry(
                    kind: .review(.commented),
                    comment: ReviewComment(
                        id: "demo-conversation-review", author: jonas,
                        body: "Looks good overall. One question about rounding inline.", createdAt: ago(5), url: url)),
                ConversationEntry(
                    kind: .review(.approved),
                    comment: ReviewComment(id: "demo-conversation-approval", author: jonas, body: "", createdAt: ago(2))
                ),
                ConversationEntry(
                    kind: .comment,
                    comment: ReviewComment(
                        id: "demo-conversation-marc", author: DemoReviewService.viewer,
                        body: "Thanks! I'll check the PDF totals against the export before approving.",
                        createdAt: ago(1), url: url, viewerCanUpdate: true, viewerCanDelete: true)),
            ])
    }
}
