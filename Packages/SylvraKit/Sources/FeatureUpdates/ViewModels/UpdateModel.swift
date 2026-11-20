import Foundation
import Observation
import Platform
import SylvraCore

/// Finds new Sylvra releases on GitHub and installs them on request (see specs/ux.md §13.1).
@MainActor
@Observable
public final class UpdateModel {
    public enum State: Equatable {
        case idle
        case checking
        /// Shown after *Check for Updates…* only.
        case upToDate
        case available(AppRelease)
        case downloading(AppRelease, progress: Double)
        case verifying(AppRelease)
        /// Ready: Sylvra quits and opens the new version.
        case relaunching(AppRelease)
        /// Can't replace the app in place: the disk image is shown in the Finder.
        case downloaded(AppRelease)
        case failed(AppRelease?, String)
    }

    public private(set) var state: State = .idle
    /// The update card is shown (a found update keeps a toolbar button when the card is closed with *Later*).
    public var isCardPresented = false
    public let currentVersion: ReleaseVersion?

    /// The release that is waiting (shown as a toolbar button after *Later*).
    public var pendingRelease: AppRelease? {
        switch state {
        case .available(let release), .downloading(let release, _), .verifying(let release),
            .relaunching(let release), .downloaded(let release):
            release
        case .failed(let release, _): release
        case .idle, .checking, .upToDate: nil
        }
    }

    public var isWorking: Bool {
        switch state {
        case .checking, .downloading, .verifying, .relaunching: true
        default: false
        }
    }

    public var automaticallyChecks: Bool {
        get { defaults?.object(forKey: Self.automaticKey) as? Bool ?? true }
        set { defaults?.set(newValue, forKey: Self.automaticKey) }
    }

    public var canInstallInPlace: Bool { installer.canReplaceApp }

    public static let automaticKey = UpdatePreferences.automaticChecksKey
    static let skippedKey = "updates.skippedVersion"
    /// Time between automatic checks while Sylvra runs.
    public static let checkInterval: Duration = .seconds(6 * 3600)

    private let fetcher: any ReleaseFetching
    private let installer: any UpdateInstalling
    private let defaults: UserDefaults?
    private static let logger = SylvraLog.logger("updates")

    /// - Parameters:
    ///   - currentVersion: the running version (`CFBundleShortVersionString`).
    ///   - defaults: stores the setting and a skipped version (`nil` in tests).
    public init(
        fetcher: any ReleaseFetching, installer: any UpdateInstalling, currentVersion: ReleaseVersion?,
        defaults: UserDefaults? = .standard
    ) {
        self.fetcher = fetcher
        self.installer = installer
        self.currentVersion = currentVersion
        self.defaults = defaults
    }

    // MARK: Checking

    /// At launch and every `checkInterval` while automatic checks are on.
    public func keepChecking() async {
        while !Task.isCancelled {
            if automaticallyChecks { await check(userInitiated: false) }
            try? await Task.sleep(for: Self.checkInterval)
        }
    }

    /// Looks for a newer release. Automatic checks stay silent unless one is found (and not skipped);
    /// *Check for Updates…* always answers, also when a skipped version is the newest.
    public func check(userInitiated: Bool) async {
        guard !isWorking else { return }
        if userInitiated {
            state = .checking
            isCardPresented = true
        }
        do {
            guard let release = try await fetcher.latestRelease(), let current = currentVersion,
                release.version > current
            else {
                if userInitiated { state = .upToDate } else if case .checking = state { state = .idle }
                return
            }
            if !userInitiated, release.version.description == skippedVersion {
                if case .checking = state { state = .idle }
                return
            }
            // A release already shown stays as it is (no card popping up again every few hours).
            if !userInitiated, pendingRelease == release { return }
            state = .available(release)
            isCardPresented = true
        } catch {
            Self.logger.error("Checking for updates failed: \(String(describing: error), privacy: .public)")
            if userInitiated { state = .failed(nil, error.localizedDescription) }
        }
    }

    private var isBusyInstalling: Bool {
        switch state {
        case .downloading, .verifying, .relaunching: true
        default: false
        }
    }

    // MARK: Actions

    /// Downloads, verifies and relaunches into the new version (or shows the disk image when the app can't be
    /// replaced where it is).
    public func install() async {
        guard let release = pendingRelease, !isBusyInstalling else { return }
        state = .downloading(release, progress: 0)
        do {
            let image = try await installer.download(release) { [weak self] fraction in
                Task { @MainActor in self?.reportProgress(fraction, for: release) }
            }
            guard installer.canReplaceApp else {
                state = .downloaded(release)
                installer.reveal(diskImage: image)
                return
            }
            state = .verifying(release)
            let prepared = try await installer.prepare(diskImage: image)
            state = .relaunching(release)
            // A moment to read "Restarting…", then the swap.
            try? await Task.sleep(for: .milliseconds(600))
            installer.relaunch(with: prepared)
        } catch {
            Self.logger.error(
                "Installing \(release.version.description, privacy: .public) failed: \(String(describing: error), privacy: .public)"
            )
            state = .failed(release, error.localizedDescription)
        }
    }

    private func reportProgress(_ fraction: Double, for release: AppRelease) {
        guard case .downloading(let current, let old) = state, current == release, fraction > old else { return }
        state = .downloading(release, progress: fraction)
    }

    /// Closes the card; the toolbar keeps a button for the update.
    public func later() {
        isCardPresented = false
        if case .upToDate = state { state = .idle }
        if case .failed(nil, _) = state { state = .idle }
    }

    /// No more reminders for this version (a newer one is announced again).
    public func skip() {
        if let release = pendingRelease { defaults?.set(release.version.description, forKey: Self.skippedKey) }
        isCardPresented = false
        state = .idle
    }

    /// Demos and screenshots: shows `state` without looking on GitHub.
    public func present(_ state: State, card: Bool = true) {
        self.state = state
        isCardPresented = card
    }

    private var skippedVersion: String? { defaults?.string(forKey: Self.skippedKey) }
}
