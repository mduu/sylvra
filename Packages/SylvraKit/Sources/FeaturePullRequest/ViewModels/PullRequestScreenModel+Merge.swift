import Foundation
import SylvraCore

extension PullRequestScreenModel {
    /// What the merge button does for the shown pull request (`nil`: no button).
    public var mergeAction: MergeOptions.Action? {
        guard merger != nil, let detail, detail.state == .open else { return nil }
        return detail.mergeOptions?.action(for: detail.mergeStatus)
    }

    /// Merging past the branch rules is possible for the shown pull request.
    public var canBypassRules: Bool {
        guard merger != nil, let detail, detail.state == .open else { return false }
        return detail.mergeOptions?.canBypassRules(for: detail.mergeStatus) ?? false
    }

    /// Opens the merge sheet with the method last used in this repository (else GitHub's default).
    /// `bypassingRules`: for a merge past the branch rules instead of the regular action.
    public func startMerge(bypassingRules: Bool = false) {
        guard let detail, let options = detail.mergeOptions else { return }
        guard let action = bypassingRules ? (canBypassRules ? .bypassRules : nil) : mergeAction else { return }
        pendingMergeAction = action
        let remembered = defaults?.string(forKey: Self.methodKey(detail.summary.id))
            .flatMap(MergeMethod.init(rawValue:))
        mergeMethod = remembered.flatMap { options.methods.contains($0) ? $0 : nil } ?? options.methods.first ?? .merge
        mergeError = nil
        isMergeSheetPresented = true
    }

    /// Carries out the sheet's action on GitHub (the user's click). The sheet closes on success; a refusal is
    /// shown in it.
    public func confirmMerge() async {
        guard let merger, let detail, let options = detail.mergeOptions, let action = pendingMergeAction, !isMerging
        else { return }
        isMerging = true
        mergeError = nil
        defer { isMerging = false }
        let method = mergeMethod
        do {
            switch action {
            case .merge, .bypassRules:
                try await merger.merge(options, method: method, expectedHeadSHA: detail.headSHA)
            case .enableAutoMerge: try await merger.enableAutoMerge(options, method: method)
            case .disableAutoMerge: try await merger.disableAutoMerge(options)
            }
        } catch {
            mergeError = (error as? LocalizedError)?.errorDescription ?? String(describing: error)
            return
        }
        if action != .disableAutoMerge { defaults?.set(method.rawValue, forKey: Self.methodKey(detail.summary.id)) }
        isMergeSheetPresented = false
        await refresh()
        if action == .merge || action == .bypassRules { onMerged?(detail.summary.id) }
    }

    static func methodKey(_ id: PullRequestID) -> String { "merge.method.\(id.owner)/\(id.repository)" }
}
