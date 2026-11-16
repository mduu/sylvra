import Foundation
import OSLog
import Observation
import Platform
import SylvraCore

/// A comment being written on a diff location.
public struct CommentDraft: Equatable, Sendable {
    public var location: CodeLocation
    /// Text of the commented lines, used for *Insert suggestion*.
    public var lineText: String
    public var body: String = ""

    public init(location: CodeLocation, lineText: String, body: String = "") {
        self.location = location
        self.lineText = lineText
        self.body = body
    }
}

/// State of the review: threads, drafts, the pending review and its submission.
@MainActor
@Observable
public final class ReviewScreenModel {
    public enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    public private(set) var snapshot: ReviewSnapshot? {
        didSet { threadsByAnchor = Dictionary(grouping: snapshot?.threads ?? [], by: \.location.anchor) }
    }
    public private(set) var loadState: LoadState = .idle
    /// The new comment being written, shown below its line.
    public var draft: CommentDraft?
    /// Reply texts per thread ID.
    public var replyDrafts: [String: String] = [:]
    /// Edited bodies per comment ID while editing.
    public var editDrafts: [String: String] = [:]
    public var isSubmitSheetPresented = false
    public var submitBody = ""
    public var submitEvent: ReviewEvent = .comment
    /// A write is in flight.
    public private(set) var isWorking = false
    public var errorMessage: String?

    private var threadsByAnchor: [CodeLocation: [ReviewThread]] = [:]
    /// Threads the reviewer expanded or collapsed against their default.
    private var toggledThreadIDs: Set<String> = []
    private var pullRequestID: PullRequestID?
    private let service: any ReviewService
    private let logger = SylvraLog.logger("review")

    public init(service: any ReviewService) {
        self.service = service
    }

    // MARK: - Queries

    public var threads: [ReviewThread] { snapshot?.threads ?? [] }
    public var hasPendingReview: Bool { snapshot?.pendingReviewID != nil }

    /// Comments of the viewer's pending review, with their threads.
    public var pendingComments: [(thread: ReviewThread, comment: ReviewComment)] {
        threads.flatMap { thread in thread.comments.filter(\.isPending).map { (thread, $0) } }
    }

    public var pendingCount: Int { threads.reduce(0) { $0 + $1.comments.count(where: \.isPending) } }

    public func threads(at location: CodeLocation) -> [ReviewThread] { threadsByAnchor[location.anchor] ?? [] }

    public func isDraftAnchored(at location: CodeLocation) -> Bool { draft?.location.anchor == location.anchor }

    public func isCollapsed(_ thread: ReviewThread) -> Bool {
        thread.isCollapsedByDefault != toggledThreadIDs.contains(thread.id)
    }

    public func toggleCollapsed(_ thread: ReviewThread) {
        if toggledThreadIDs.contains(thread.id) {
            toggledThreadIDs.remove(thread.id)
        } else {
            toggledThreadIDs.insert(thread.id)
        }
    }

    // MARK: - Loading

    public func load(_ id: PullRequestID?) async {
        // Switching pull requests discards per-PR state (a draft started before the first load is kept).
        guard let id else {
            if pullRequestID != nil { reset() }
            return
        }
        if pullRequestID != id {
            if pullRequestID != nil { reset() }
            loadState = .loading
        }
        pullRequestID = id
        do {
            let loaded = try await service.loadReview(for: id)
            guard !Task.isCancelled else { return }
            snapshot = loaded
            loadState = .loaded
        } catch {
            guard !Task.isCancelled else { return }
            loadState = .failed(String(describing: error))
        }
    }

    private func reset() {
        snapshot = nil
        loadState = .idle
        draft = nil
        replyDrafts = [:]
        editDrafts = [:]
        toggledThreadIDs = []
        pullRequestID = nil
    }

    // MARK: - Composer

    // MARK: - Comment language and rewriting

    /// Rewrites a comment draft personally in a language (`English`, `German`); provided by the app (AI agent).
    public typealias Rewriter =
        @Sendable (_ text: String, _ language: String, _ style: CommentRewriteStyle) async throws -> String

    public var rewriter: Rewriter?
    /// Hands the draft's lines and text to a private AI discussion (wired by the app).
    public var discussHandler: ((_ location: CodeLocation, _ code: String, _ question: String) -> Void)?
    /// What the AI is doing with the draft right now (`nil`: nothing).
    public private(set) var rewritingStyle: CommentRewriteStyle?
    public var isRewriting: Bool { rewritingStyle != nil }
    private var rewriteTask: Task<Void, Never>?
    /// The draft text before the last AI rewrite, for *Undo rewrite*.
    public private(set) var textBeforeRewrite: String?
    /// Default when a repository has no remembered choice yet.
    public var defaultCommentLanguage = "English"

    /// Language of the current draft; remembered per repository (comments switch between German and English).
    public var draftLanguage: String {
        get {
            guard let pullRequestID else { return defaultCommentLanguage }
            return UserDefaults.standard.string(forKey: Self.languageKey(pullRequestID)) ?? defaultCommentLanguage
        }
        set {
            if let pullRequestID { UserDefaults.standard.set(newValue, forKey: Self.languageKey(pullRequestID)) }
            languageRevision += 1
            // A new language replaces a translation that is still running.
            if rewritingStyle == .translate { cancelRewrite() }
            Task { await rewriteDraft(.translate) }
        }
    }

    /// Bumped when the language changes so views observing `draftLanguage` refresh.
    public private(set) var languageRevision = 0

    private static func languageKey(_ id: PullRequestID) -> String { "commentLanguage.\(id.owner)/\(id.repository)" }

    /// Starts a comment on a location (from the diff gutter). Keeps the text when only the range changes.
    public func startComment(at location: CodeLocation, lineText: String) {
        if let current = draft, current.location.path == location.path, current.location.side == location.side,
            current.location.lines.overlaps(location.lines)
        {
            draft?.location = location
            draft?.lineText = lineText
        } else {
            draft = CommentDraft(location: location, lineText: lineText)
        }
    }

    public func cancelDraft() {
        cancelRewrite()
        draft = nil
    }

    /// Appends a ```` ```suggestion ```` block with the commented lines to the draft.
    public func insertSuggestion() {
        guard let draft else { return }
        self.draft?.body = SuggestionBlock.insert(code: draft.lineText, into: draft.body)
    }

    /// Adds the draft to the pending review, creating the pending review if needed.
    public func addDraftToReview() async {
        guard let draft, canPost(draft.body), let nodeID = snapshot?.pullRequestNodeID else { return }
        let started = pullRequestID
        await perform("add comment") {
            let reviewID = try await self.ensurePendingReview(nodeID: nodeID, for: started)
            let thread = try await self.service.addThread(
                reviewID: reviewID, location: draft.location, body: draft.body)
            // The reviewer may have switched PRs meanwhile — never write results into another PR.
            guard self.pullRequestID == started else { return }
            self.snapshot?.threads.append(thread)
            self.draft = nil
        }
    }

    /// Posts the draft immediately as a single comment (only without a pending review, like GitHub).
    public func postDraftNow() async {
        guard let draft, canPost(draft.body), !hasPendingReview, let nodeID = snapshot?.pullRequestNodeID else {
            return
        }
        let started = pullRequestID
        await perform("post comment") {
            try await self.service.postComment(pullRequestNodeID: nodeID, location: draft.location, body: draft.body)
            guard self.pullRequestID == started else { return }
            self.draft = nil
            try await self.reload()
        }
    }

    // MARK: - Threads

    /// Replies to a thread; part of the pending review if one exists, otherwise posted immediately.
    public func reply(to thread: ReviewThread) async {
        let body = replyDrafts[thread.id] ?? ""
        guard canPost(body) else { return }
        let started = pullRequestID
        await perform("reply") {
            let comment = try await self.service.reply(
                threadID: thread.id, reviewID: self.snapshot?.pendingReviewID, body: body)
            guard self.pullRequestID == started else { return }
            self.updateThread(thread.id) { $0.comments.append(comment) }
            self.replyDrafts[thread.id] = nil
        }
    }

    public func setResolved(_ resolved: Bool, thread: ReviewThread) async {
        updateThread(thread.id) { $0.isResolved = resolved }
        toggledThreadIDs.remove(thread.id)
        await perform(resolved ? "resolve" : "unresolve") {
            try await self.service.setResolved(resolved, threadID: thread.id)
        } rollback: {
            self.updateThread(thread.id) { $0.isResolved = !resolved }
        }
    }

    public func beginEditing(_ comment: ReviewComment) { editDrafts[comment.id] = comment.body }

    public func cancelEditing(_ comment: ReviewComment) { editDrafts[comment.id] = nil }

    public func saveEdit(of comment: ReviewComment) async {
        guard let body = editDrafts[comment.id], canPost(body) else { return }
        await perform("edit comment") {
            let updated = try await self.service.updateComment(id: comment.id, body: body)
            self.updateComment(comment.id) { $0.body = updated.body }
            self.editDrafts[comment.id] = nil
        }
    }

    /// Toggles the viewer's reaction (optimistic, rolled back on failure). Reactions post immediately on GitHub.
    public func toggleReaction(_ reaction: Reaction, on comment: ReviewComment) async {
        let current = snapshot?.threads.lazy.flatMap(\.comments).first { $0.id == comment.id }?.reactions ?? []
        let added = !(current.first { $0.reaction == reaction }?.viewerHasReacted ?? false)
        updateComment(comment.id) { $0.reactions = $0.reactions.toggling(reaction) }
        await perform(added ? "add reaction" : "remove reaction") {
            try await self.service.setReaction(reaction, added: added, commentID: comment.id)
        } rollback: {
            self.updateComment(comment.id) { $0.reactions = $0.reactions.toggling(reaction) }
        }
    }

    public func delete(_ comment: ReviewComment) async {
        await perform("delete comment") {
            try await self.service.deleteComment(id: comment.id)
            guard var threads = self.snapshot?.threads else { return }
            for index in threads.indices { threads[index].comments.removeAll { $0.id == comment.id } }
            self.snapshot?.threads = threads.filter { !$0.comments.isEmpty }
        }
    }

    // MARK: - Submit

    /// Submits the pending review (or a review without inline comments) and reloads the threads.
    public func submitReview() async {
        guard let nodeID = snapshot?.pullRequestNodeID else { return }
        if submitEvent == .requestChanges, submitBody.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty {
            errorMessage = String(localized: "Requesting changes needs a summary.")
            return
        }
        let reviewID = snapshot?.pendingReviewID
        let started = pullRequestID
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

    // MARK: - Helpers

    private func canPost(_ body: String) -> Bool {
        !isWorking && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func ensurePendingReview(nodeID: String, for pullRequest: PullRequestID?) async throws -> String {
        if let id = snapshot?.pendingReviewID { return id }
        let id = try await service.startPendingReview(pullRequestNodeID: nodeID)
        if pullRequestID == pullRequest { snapshot?.pendingReviewID = id }
        return id
    }

    private func reload() async throws {
        guard let pullRequestID else { return }
        snapshot = try await service.loadReview(for: pullRequestID)
    }

    private func updateThread(_ id: String, _ change: (inout ReviewThread) -> Void) {
        guard var thread = snapshot?.threads.first(where: { $0.id == id }),
            let index = snapshot?.threads.firstIndex(where: { $0.id == id })
        else { return }
        change(&thread)
        snapshot?.threads[index] = thread
    }

    private func updateComment(_ id: String, _ change: (inout ReviewComment) -> Void) {
        guard let threads = snapshot?.threads,
            let threadIndex = threads.firstIndex(where: { $0.comments.contains { $0.id == id } }),
            let index = threads[threadIndex].comments.firstIndex(where: { $0.id == id })
        else { return }
        var comment = threads[threadIndex].comments[index]
        change(&comment)
        snapshot?.threads[threadIndex].comments[index] = comment
    }

    private func perform(
        _ action: String, _ work: () async throws -> Void, rollback: (() -> Void)? = nil
    ) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
        } catch {
            logger.error("Review action '\(action, privacy: .public)' failed: \(String(describing: error))")
            rollback?()
            errorMessage = String(localized: "Couldn't \(action): \(error.localizedDescription)")
        }
    }
}

// MARK: - AI writing help

extension ReviewScreenModel {
    /// Moves the draft into a private discussion with the agent instead of commenting.
    public func discussDraft() {
        guard let draft, let discussHandler else { return }
        discussHandler(draft.location, draft.lineText, draft.body)
        cancelDraft()
    }

    /// Rewrites the draft in `draftLanguage`; suggestion blocks are kept verbatim by the rewriter.
    public func rewriteDraft(_ style: CommentRewriteStyle = .improve) async {
        guard let rewriter, let draft, !draft.body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty,
            !isRewriting
        else { return }
        let started = pullRequestID
        let location = draft.location
        let original = draft.body
        let language = draftLanguage
        rewritingStyle = style
        let task = Task { @MainActor in
            do {
                let rewritten = try await rewriter(original, language, style)
                // Only replace the text if the reviewer is still on the same draft and didn't cancel.
                guard !Task.isCancelled, pullRequestID == started, self.draft?.location == location else { return }
                self.draft?.body = rewritten
                textBeforeRewrite = original
            } catch {
                guard !Task.isCancelled, !(error is CancellationError) else { return }
                errorMessage = String(localized: "Couldn't rewrite: \(error.localizedDescription)")
            }
        }
        rewriteTask = task
        await task.value
        if rewriteTask == task {
            rewriteTask = nil
            rewritingStyle = nil
        }
    }

    /// Stops a running rewrite or translation; the draft keeps its current text.
    public func cancelRewrite() {
        rewriteTask?.cancel()
        rewriteTask = nil
        rewritingStyle = nil
    }

    /// Restores the draft text from before the last AI rewrite.
    public func undoRewrite() {
        guard let textBeforeRewrite, draft != nil else { return }
        draft?.body = textBeforeRewrite
        self.textBeforeRewrite = nil
    }
}
