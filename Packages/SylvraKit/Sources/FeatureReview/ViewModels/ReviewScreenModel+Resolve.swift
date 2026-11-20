import Foundation

// MARK: - Resolving threads

extension ReviewScreenModel {
    public func setResolved(_ resolved: Bool, thread: ReviewThread) async {
        await setResolved(resolved, threadID: thread.id)
    }

    /// Resolves or reopens a thread, also one the diff doesn't show (from the Comments tab); `false` on failure.
    @discardableResult
    public func setResolved(_ resolved: Bool, threadID: String) async -> Bool {
        updateThread(threadID) { $0.isResolved = resolved }
        toggledThreadIDs.remove(threadID)
        var succeeded = true
        await perform(resolved ? "resolve" : "unresolve") {
            try await self.service.setResolved(resolved, threadID: threadID)
        } rollback: {
            self.updateThread(threadID) { $0.isResolved = !resolved }
            succeeded = false
        }
        if succeeded { onResolvedChange?(threadID, resolved) }
        return succeeded
    }
}
