import Foundation
import SylvraCore

/// Fixture threads for `--demo`, previews and tests. Writes only change local state.
public actor DemoReviewService: ReviewService {
    private var snapshot: ReviewSnapshot
    private var nextID = 1

    public init(snapshot: ReviewSnapshot = DemoReviewService.sample()) {
        self.snapshot = snapshot
    }

    public func loadReview(for id: PullRequestID) async throws -> ReviewSnapshot { snapshot }

    public func startPendingReview(pullRequestNodeID: String) async throws -> String {
        let id = makeID("review")
        snapshot.pendingReviewID = id
        return id
    }

    public func addThread(reviewID: String, location: CodeLocation, body: String) async throws -> ReviewThread {
        let thread = ReviewThread(
            id: makeID("thread"), location: location, comments: [comment(body, isPending: true)])
        snapshot.threads.append(thread)
        return thread
    }

    public func postComment(pullRequestNodeID: String, location: CodeLocation, body: String) async throws {
        snapshot.threads.append(
            ReviewThread(id: makeID("thread"), location: location, comments: [comment(body, isPending: false)]))
    }

    public func reply(threadID: String, reviewID: String?, body: String) async throws -> ReviewComment {
        let reply = comment(body, isPending: reviewID != nil)
        update(threadID) { $0.comments.append(reply) }
        return reply
    }

    public func setResolved(_ resolved: Bool, threadID: String) async throws {
        update(threadID) { $0.isResolved = resolved }
    }

    public func updateComment(id: String, body: String) async throws -> ReviewComment {
        for (threadIndex, thread) in snapshot.threads.enumerated() {
            if let index = thread.comments.firstIndex(where: { $0.id == id }) {
                snapshot.threads[threadIndex].comments[index].body = body
                return snapshot.threads[threadIndex].comments[index]
            }
        }
        throw DemoReviewError.notFound
    }

    public func deleteComment(id: String) async throws {
        for index in snapshot.threads.indices { snapshot.threads[index].comments.removeAll { $0.id == id } }
        snapshot.threads.removeAll { $0.comments.isEmpty }
    }

    public func setReaction(_ reaction: Reaction, added: Bool, commentID: String) async throws {
        for (threadIndex, thread) in snapshot.threads.enumerated() {
            guard let index = thread.comments.firstIndex(where: { $0.id == commentID }) else { continue }
            let current = snapshot.threads[threadIndex].comments[index].reactions
            let reacted = current.first { $0.reaction == reaction }?.viewerHasReacted ?? false
            if reacted != added { snapshot.threads[threadIndex].comments[index].reactions = current.toggling(reaction) }
            return
        }
        throw DemoReviewError.notFound
    }

    public func submitReview(pullRequestNodeID: String, reviewID: String?, event: ReviewEvent, body: String)
        async throws
    {
        snapshot.pendingReviewID = nil
        snapshot.threads = snapshot.threads.map { thread in
            var thread = thread
            thread.comments = thread.comments.map { $0.submitted }
            return thread
        }
    }

    // MARK: - Helpers

    private func makeID(_ prefix: String) -> String {
        defer { nextID += 1 }
        return "demo-\(prefix)-\(nextID)"
    }

    private func comment(_ body: String, isPending: Bool) -> ReviewComment {
        ReviewComment(
            id: makeID("comment"), author: Self.viewer, body: body, createdAt: .now, isPending: isPending,
            viewerCanUpdate: true, viewerCanDelete: true)
    }

    private func update(_ threadID: String, _ change: (inout ReviewThread) -> Void) {
        guard let index = snapshot.threads.firstIndex(where: { $0.id == threadID }) else { return }
        change(&snapshot.threads[index])
    }

    // MARK: - Fixtures

    static let viewer = UserRef(login: "mduu", name: "Marc Dürst")

    /// Threads on the demo diff (`Sources/Billing/InvoiceService.swift` and `Sources/Export/ExportFormat.swift`).
    public static func sample(now: Date = .now) -> ReviewSnapshot {
        let lena = UserRef(login: "lkeller", name: "Lena Keller")
        let jonas = UserRef(login: "jmeier", name: "Jonas Meier")
        func ago(_ hours: Double) -> Date { now.addingTimeInterval(-hours * 3600) }
        let url = URL(string: "https://github.com/acme/billing/pull/1234")
        let rounding = ReviewThread(
            id: "demo-thread-rounding",
            location: CodeLocation(path: "Sources/Billing/InvoiceService.swift", line: 9, side: .right),
            comments: [
                ReviewComment(
                    id: "demo-c1", author: jonas,
                    body: "Rounding each line before summing can drift from the invoice total by a few cents. "
                        + "Should we round **once** at the end instead?",
                    createdAt: ago(5), url: url,
                    reactions: [
                        ReactionGroup(reaction: .thumbsUp, count: 2), ReactionGroup(reaction: .eyes, count: 1),
                    ]),
                ReviewComment(
                    id: "demo-c2", author: lena,
                    body: "Accounting wants per-line rounding to match the PDF (see BILL-311). "
                        + "I'll add a test that documents it.",
                    createdAt: ago(3), url: url),
            ])
        let csv = ReviewThread(
            id: "demo-thread-csv",
            location: CodeLocation(path: "Sources/Billing/InvoiceService.swift", line: 16, side: .right),
            isResolved: true,
            comments: [
                ReviewComment(
                    id: "demo-c3", author: jonas, body: "Names with commas will break the CSV — please escape them.",
                    createdAt: ago(20), url: url),
                ReviewComment(
                    id: "demo-c4", author: lena, body: "Done in `CSVEncoder`, quoted per RFC 4180.",
                    createdAt: ago(18), url: url),
            ])
        let format = ReviewThread(
            id: "demo-thread-format",
            location: CodeLocation(path: "Sources/Export/ExportFormat.swift", line: 1, side: .right),
            comments: [
                ReviewComment(
                    id: "demo-c5", author: viewer,
                    body: "Making it `String`-backed lets the export menu list the formats:\n\n"
                        + SuggestionBlock.make(code: "enum ExportFormat: String, CaseIterable {"),
                    createdAt: ago(1), url: url, isPending: true, viewerCanUpdate: true, viewerCanDelete: true)
            ])
        return ReviewSnapshot(
            pullRequestNodeID: "demo", threads: [rounding, csv, format], pendingReviewID: "demo-review")
    }
}

enum DemoReviewError: Error {
    case notFound
}

extension ReviewComment {
    /// The comment after its review was submitted.
    var submitted: ReviewComment {
        ReviewComment(
            id: id, author: author, body: body, createdAt: createdAt, url: url, isPending: false,
            viewerCanUpdate: viewerCanUpdate, viewerCanDelete: viewerCanDelete)
    }
}
