import Foundation
import SylvraCore

extension PullRequestScreenModel {
    /// What the merge button does for the shown pull request (`nil`: no button).
    public var mergeAction: MergeOptions.Action? {
        guard merger != nil, let detail, detail.state == .open else { return nil }
        return detail.mergeOptions?.action(for: detail.mergeStatus)
    }

    /// Opens the merge sheet with the method last used in this repository (else GitHub's default).
    public func startMerge() {
        guard let detail, let options = detail.mergeOptions, mergeAction != nil else { return }
        let remembered = defaults?.string(forKey: Self.methodKey(detail.summary.id))
            .flatMap(MergeMethod.init(rawValue:))
        mergeMethod = remembered.flatMap { options.methods.contains($0) ? $0 : nil } ?? options.methods.first ?? .merge
        mergeError = nil
        isMergeSheetPresented = true
    }

    /// Carries out the sheet's action on GitHub (the user's click). The sheet closes on success; a refusal is
    /// shown in it.
    public func confirmMerge() async {
        guard let merger, let detail, let options = detail.mergeOptions, let action = mergeAction, !isMerging
        else { return }
        isMerging = true
        mergeError = nil
        defer { isMerging = false }
        let method = mergeMethod
        do {
            switch action {
            case .merge: try await merger.merge(options, method: method, expectedHeadSHA: detail.headSHA)
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
    }

    static func methodKey(_ id: PullRequestID) -> String { "merge.method.\(id.owner)/\(id.repository)" }
}
