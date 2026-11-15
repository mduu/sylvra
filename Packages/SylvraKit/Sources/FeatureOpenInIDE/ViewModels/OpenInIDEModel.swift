import Foundation
import Observation
import SylvraCore

/// Opens pull requests in the chosen IDE and remembers the choice per repository.
@MainActor
@Observable
public final class OpenInIDEModel {
    public enum Status: Equatable {
        case idle
        case working(String)
        case done(String)
        case failed(String)
    }

    public private(set) var installedIDEs: [IDE] = []
    public private(set) var status: Status = .idle
    /// Set when the main clone is dirty — the UI asks whether to stash.
    public var stashConfirmation: StashRequest?

    public struct StashRequest: Identifiable, Equatable {
        public var id: String { pullRequest.description }
        public let pullRequest: PullRequestID
        public let ide: IDE
        public let clone: URL
    }

    private let checkout: any CheckoutPreparing
    private let opener: any IDEOpening
    private let defaults: UserDefaults

    public init(checkout: any CheckoutPreparing, opener: any IDEOpening, defaults: UserDefaults = .standard) {
        self.checkout = checkout
        self.opener = opener
        self.defaults = defaults
        installedIDEs = opener.installedIDEs()
    }

    // MARK: Preferences per repository

    public func preferredIDE(for id: PullRequestID) -> IDE {
        let stored = defaults.string(forKey: key("ide", id)).flatMap(IDE.Kind.init(rawValue:))
        return installedIDEs.first { $0.kind == stored } ?? installedIDEs.first ?? .defaultApp
    }

    public func checkoutTarget(for id: PullRequestID) -> CheckoutTarget {
        defaults.string(forKey: key("checkout", id)).flatMap(CheckoutTarget.init(rawValue:)) ?? .worktree
    }

    public func setCheckoutTarget(_ target: CheckoutTarget, for id: PullRequestID) {
        defaults.set(target.rawValue, forKey: key("checkout", id))
    }

    private func key(_ name: String, _ id: PullRequestID) -> String {
        "openInIDE.\(name).\(id.owner)/\(id.repository)"
    }

    // MARK: Opening

    /// Checks out the PR head and opens it in `ide` (remembered as the repo's default).
    public func open(_ id: PullRequestID, in ide: IDE? = nil, file: String? = nil, line: Int? = nil) async {
        let ide = ide ?? preferredIDE(for: id)
        defaults.set(ide.kind.rawValue, forKey: key("ide", id))
        await run(id, ide: ide, file: file, line: line, stash: false)
    }

    /// The user agreed to stash uncommitted changes in the main clone.
    public func confirmStash() async {
        guard let request = stashConfirmation else { return }
        stashConfirmation = nil
        await run(request.pullRequest, ide: request.ide, file: nil, line: nil, stash: true)
    }

    private func run(_ id: PullRequestID, ide: IDE, file: String?, line: Int?, stash: Bool) async {
        let target = checkoutTarget(for: id)
        status = .working(
            target == .worktree
                ? String(localized: "Preparing review worktree…") : String(localized: "Checking out in main clone…"))
        do {
            let directory: URL
            switch target {
            case .worktree:
                directory = try await checkout.prepareWorktree(for: id)
            case .mainClone:
                directory = try await checkout.prepareMainClone(for: id, stashChanges: stash).clone
            }
            try await opener.open(
                ide, directory: directory, file: file.map { directory.appending(path: $0) }, line: line)
            status = .done(
                stash
                    ? String(
                        localized:
                            "Opened in \(ide.name) — your changes are in a stash named “Sylvra: before reviewing …”")
                    : String(localized: "Opened in \(ide.name)"))
            clearStatusLater()
        } catch CheckoutError.dirtyWorkingTree(let clone) {
            status = .idle
            stashConfirmation = StashRequest(pullRequest: id, ide: ide, clone: clone)
        } catch {
            status = .failed(Self.message(for: error))
            clearStatusLater(after: .seconds(8))
        }
    }

    private func clearStatusLater(after delay: Duration = .seconds(3)) {
        let shown = status
        Task {
            try? await Task.sleep(for: delay)
            if status == shown { status = .idle }
        }
    }

    private static func message(for error: any Error) -> String {
        switch error {
        case CheckoutError.noLocalClone(let repository):
            String(localized: "No local clone of \(repository) found. Use the review worktree instead.")
        default:
            String(describing: error)
        }
    }
}
