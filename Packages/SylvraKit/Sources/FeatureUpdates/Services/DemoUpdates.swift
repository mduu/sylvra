import Foundation

/// Fixture release and states for demos and screenshots (`--update=<state>`); never touches GitHub.
public enum DemoUpdates {
    public static let release = AppRelease(
        version: ReleaseVersion(parts: [0, 6, 0]),
        notes: """
            - Sylvra keeps itself up to date: new versions are announced here and install with one click
            - AI findings of several models are combined, duplicates disappear
            - Resolve code comments right from the *Comments* tab and jump to them in the diff
            - Smoother column resizing and a spinner while the inbox refreshes
            """,
        diskImage: URL(filePath: "/dev/null"),
        diskImageSize: 18_400_000,
        page: URL(string: "https://github.com/mduu/sylvra/releases"),
        publishedAt: Date(timeIntervalSinceNow: -3 * 3600))

    /// The state for `--update=<name>`: checking, upToDate, available, downloading, verifying, relaunching,
    /// downloaded, failed, failedCheck; `later` is the toolbar button after *Later*.
    public static func state(named name: String) -> (state: UpdateModel.State, card: Bool)? {
        if name == "later" { return (.available(release), false) }
        let states: [String: UpdateModel.State] = [
            "checking": .checking,
            "upToDate": .upToDate,
            "available": .available(release),
            "downloading": .downloading(release, progress: 0.62),
            "verifying": .verifying(release),
            "relaunching": .relaunching(release),
            "downloaded": .downloaded(release),
            "failed": .failed(release, String(localized: "The download stopped: the network connection was lost.")),
            "failedCheck": .failed(
                nil, String(localized: "GitHub didn't answer. Check your connection and try again.")),
        ]
        return states[name].map { ($0, true) }
    }
}

/// Never finds anything (demo launches don't look on GitHub).
public struct DemoReleaseFetcher: ReleaseFetching {
    public init() {}
    public func latestRelease() async throws -> AppRelease? { nil }
}

/// Walks through download, check and relaunch without touching anything (demo launches).
public struct DemoUpdateInstaller: UpdateInstalling {
    public init() {}

    public var canReplaceApp: Bool { true }

    public func download(_ release: AppRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        for step in 1...20 {
            try await Task.sleep(for: .milliseconds(120))
            progress(Double(step) / 20)
        }
        return release.diskImage
    }

    public func prepare(diskImage: URL) async throws -> URL {
        try await Task.sleep(for: .seconds(1.5))
        return diskImage
    }

    @MainActor public func relaunch(with preparedApp: URL) {}

    @MainActor public func reveal(diskImage: URL) {}
}
