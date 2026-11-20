import Foundation
import SylvraCore

/// Prepares checkouts (abstracted for tests and demo mode).
public protocol CheckoutPreparing: Sendable {
    /// A review worktree, or the user's own checkout of `branch` when it has the PR head.
    func prepareWorktree(for id: PullRequestID, branch: String?) async throws -> URL
    func prepareMainClone(for id: PullRequestID, stashChanges: Bool) async throws -> (
        clone: URL, previousBranch: String?
    )
}

/// Detects and launches IDEs (abstracted for tests and demo mode).
@MainActor
public protocol IDEOpening {
    func installedIDEs() -> [IDE]
    func open(_ ide: IDE, directory: URL, file: URL?, line: Int?) async throws
}

extension CheckoutService: CheckoutPreparing {
    public func prepareWorktree(for id: PullRequestID, branch: String?) async throws -> URL {
        try await prepareWorktree(for: id, purpose: .ide, branch: branch)
    }
}
extension IDELauncher: IDEOpening {}

/// Demo implementations: pretend to check out and open, without touching the system.
public struct DemoCheckout: CheckoutPreparing {
    public init() {}

    public func prepareWorktree(for id: PullRequestID, branch: String?) async throws -> URL {
        try await Task.sleep(for: .milliseconds(400))
        return URL(fileURLWithPath: "/tmp/sylvra-demo/\(id.repository)")
    }

    public func prepareMainClone(for id: PullRequestID, stashChanges: Bool) async throws -> (
        clone: URL, previousBranch: String?
    ) {
        (URL(fileURLWithPath: "/tmp/sylvra-demo/\(id.repository)"), "main")
    }
}

@MainActor
public struct DemoIDEOpener: IDEOpening {
    public init() {}
    public func installedIDEs() -> [IDE] { [.rider, .vsCode, .xcode, .defaultApp] }
    public func open(_ ide: IDE, directory: URL, file: URL?, line: Int?) async throws {}
}
