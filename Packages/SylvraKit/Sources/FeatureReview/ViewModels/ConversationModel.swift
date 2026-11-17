import Foundation
import Observation
import Platform
import SylvraCore

/// State of a pull request's conversation: entries, the new comment, edits and reactions.
/// Reloads on its own while shown, so new comments by others appear without a manual refresh.
@MainActor
@Observable
public final class ConversationModel {
    public enum LoadState: Equatable {
        case idle, loading, loaded, failed(String)
    }

    /// How often the conversation is reloaded while it is shown.
    public static let refreshInterval: Duration = .seconds(60)

    public private(set) var conversation: Conversation?
    public private(set) var loadState: LoadState = .idle
    /// When the conversation was last loaded successfully.
    public private(set) var lastUpdated: Date?
    public private(set) var isRefreshing = false
    /// A write is in flight.
    public private(set) var isWorking = false
    public var errorMessage: String?
    /// Edited texts per entry ID while editing.
    public var editDrafts: [String: String] = [:]
    /// Bumped to put the cursor into the new-comment field (after *Quote reply*).
    public private(set) var composerFocusRequest = 0

    /// New-comment texts per pull request, so switching pull requests doesn't lose a draft.
    private var drafts: [PullRequestID: String] = [:]
    private(set) var pullRequestID: PullRequestID?
    private let service: any ConversationService
    private let logger = SylvraLog.logger("conversation")

    public init(service: any ConversationService) {
        self.service = service
    }

    public var entries: [ConversationEntry] { conversation?.entries ?? [] }

    /// The new comment for the current pull request.
    public var draft: String {
        get { pullRequestID.flatMap { drafts[$0] } ?? "" }
        set { if let pullRequestID { drafts[pullRequestID] = newValue } }
    }

    // MARK: - Loading

    public func load(_ id: PullRequestID?) async {
        if pullRequestID != id {
            conversation = nil
            editDrafts = [:]
            lastUpdated = nil
            loadState = id == nil ? .idle : .loading
        }
        pullRequestID = id
        guard let id else { return }
        do {
            let loaded = try await service.loadConversation(for: id)
            guard !Task.isCancelled, pullRequestID == id else { return }
            if conversation != loaded { conversation = loaded }
            loadState = .loaded
            lastUpdated = .now
        } catch {
            guard !Task.isCancelled, pullRequestID == id else { return }
            if conversation == nil { loadState = .failed(String(describing: error)) }
        }
    }

    /// Loads again now; skipped while a write is in flight (it would undo an optimistic change).
    public func refresh() async {
        guard pullRequestID != nil, !isWorking, !isRefreshing else { return }
        isRefreshing = true
        defer { isRefreshing = false }
        await load(pullRequestID)
    }

    /// Reloads every `interval` until the task is cancelled (the conversation is no longer shown).
    public func keepRefreshing(every interval: Duration = refreshInterval) async {
        while !Task.isCancelled {
            try? await Task.sleep(for: interval)
            guard !Task.isCancelled else { return }
            await refresh()
        }
    }

    // MARK: - Writing

    /// Posts the new comment right away (an explicit user action).
    public func post() async {
        let body = draft
        guard canPost(body), let nodeID = conversation?.pullRequestNodeID, let started = pullRequestID else { return }
        await perform("post comment") {
            let entry = try await self.service.addComment(pullRequestNodeID: nodeID, body: body)
            self.drafts[started] = nil
            guard self.pullRequestID == started else { return }
            self.conversation?.entries.append(entry)
        }
    }

    /// GitHub's *Quote reply*: quotes the entry in the new comment and puts the cursor there.
    public func quoteReply(to entry: ConversationEntry) {
        draft = QuoteReply.draft(quoting: entry.comment.body, into: draft)
        composerFocusRequest += 1
    }

    public func beginEditing(_ entry: ConversationEntry) { editDrafts[entry.id] = entry.comment.body }

    public func cancelEditing(_ entry: ConversationEntry) { editDrafts[entry.id] = nil }

    public func saveEdit(of entry: ConversationEntry) async {
        guard let body = editDrafts[entry.id], canPost(body) else { return }
        await perform("edit comment") {
            let stored = try await self.service.updateBody(of: entry, to: body)
            self.update(entry.id) { $0.comment.body = stored }
            self.editDrafts[entry.id] = nil
        }
    }

    public func delete(_ entry: ConversationEntry) async {
        guard entry.canDelete else { return }
        await perform("delete comment") {
            try await self.service.deleteComment(id: entry.id)
            self.conversation?.entries.removeAll { $0.id == entry.id }
        }
    }

    /// Toggles the viewer's reaction (optimistic, rolled back on failure); posts on GitHub right away.
    public func toggleReaction(_ reaction: Reaction, on entry: ConversationEntry) async {
        let current = entries.first { $0.id == entry.id }?.comment.reactions ?? []
        let added = !(current.first { $0.reaction == reaction }?.viewerHasReacted ?? false)
        update(entry.id) { $0.comment.reactions = $0.comment.reactions.toggling(reaction) }
        await perform(added ? "add reaction" : "remove reaction") {
            try await self.service.setReaction(reaction, added: added, subjectID: entry.id)
        } rollback: {
            self.update(entry.id) { $0.comment.reactions = $0.comment.reactions.toggling(reaction) }
        }
    }

    // MARK: - Helpers

    private func canPost(_ body: String) -> Bool {
        !isWorking && !body.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
    }

    private func update(_ id: String, _ change: (inout ConversationEntry) -> Void) {
        guard let index = conversation?.entries.firstIndex(where: { $0.id == id }),
            var entry = conversation?.entries[index]
        else { return }
        change(&entry)
        conversation?.entries[index] = entry
    }

    private func perform(_ action: String, _ work: () async throws -> Void, rollback: (() -> Void)? = nil) async {
        isWorking = true
        defer { isWorking = false }
        do {
            try await work()
        } catch {
            logger.error("Conversation action '\(action, privacy: .public)' failed: \(String(describing: error))")
            rollback?()
            errorMessage = String(localized: "Couldn't \(action): \(error.localizedDescription)")
        }
    }
}
