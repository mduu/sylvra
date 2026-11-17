import Foundation
import SylvraCore

/// AI writing help for the new conversation comment, like for code comments: rephrase, shorten,
/// translate when the language changes, undo.
extension ConversationModel {
    public var isRewriting: Bool { rewritingStyle != nil }

    /// Language of the new comment; remembered per repository, shared with code comments.
    public var draftLanguage: String {
        get {
            _ = languageRevision
            guard let pullRequestID else { return defaultCommentLanguage }
            return UserDefaults.standard.string(forKey: ReviewScreenModel.languageKey(pullRequestID))
                ?? defaultCommentLanguage
        }
        set {
            if let pullRequestID {
                UserDefaults.standard.set(newValue, forKey: ReviewScreenModel.languageKey(pullRequestID))
            }
            languageRevision += 1
            // A new language replaces a translation that is still running.
            if rewritingStyle == .translate { cancelRewrite() }
            Task { await rewriteDraft(.translate) }
        }
    }

    /// Rewrites the new comment in `draftLanguage`; the text is locked meanwhile.
    public func rewriteDraft(_ style: CommentRewriteStyle = .improve) async {
        let original = draft
        guard let rewriter, let started = pullRequestID, !isRewriting,
            !original.trimmingCharacters(in: .whitespacesAndNewlines).isEmpty
        else { return }
        let language = draftLanguage
        rewritingStyle = style
        let task = Task { @MainActor in
            do {
                let rewritten = try await rewriter(original, language, style)
                // Only replace the text the reviewer still has (a draft of another PR stays untouched).
                guard !Task.isCancelled, drafts[started] == original else { return }
                drafts[started] = rewritten
                if pullRequestID == started { textBeforeRewrite = original }
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

    /// Stops a running rewrite or translation; the comment keeps its current text.
    public func cancelRewrite() {
        rewriteTask?.cancel()
        rewriteTask = nil
        rewritingStyle = nil
    }

    /// Restores the text from before the last AI rewrite.
    public func undoRewrite() {
        guard let textBeforeRewrite else { return }
        draft = textBeforeRewrite
        self.textBeforeRewrite = nil
    }
}
