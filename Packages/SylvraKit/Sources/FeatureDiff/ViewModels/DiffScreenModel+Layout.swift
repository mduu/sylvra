import Foundation
import SylvraCore

// MARK: - Layout per pull request

extension DiffScreenModel {
    /// The layout last used for this pull request, otherwise the last choice made.
    func restoreLayout(for id: PullRequestID) {
        guard let defaults else { return }
        let remembered =
            DiffLayoutMemory(defaults: defaults).layout(for: id)
            ?? defaults.string(forKey: Self.layoutKey).flatMap(Layout.init(rawValue:))
        guard let remembered, remembered != layout else { return }
        isRestoringLayout = true
        layout = remembered
        isRestoringLayout = false
    }

    /// Forgets per-pull-request layouts of pull requests that were closed or not opened for a week.
    public func pruneRememberedLayouts(isOpen: @Sendable (PullRequestID) async -> Bool?) async {
        guard let defaults else { return }
        await DiffLayoutMemory(defaults: defaults).prune(isOpen: isOpen)
    }
}
