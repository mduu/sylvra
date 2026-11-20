import Foundation
import Testing

@testable import FeatureUpdates

actor FakeFetcher: ReleaseFetching {
    var release: AppRelease?
    var error: (any Error)?
    private(set) var calls = 0

    init(release: AppRelease? = nil, error: (any Error)? = nil) {
        self.release = release
        self.error = error
    }

    func latestRelease() async throws -> AppRelease? {
        calls += 1
        if let error { throw error }
        return release
    }

    func publish(_ release: AppRelease) { self.release = release }
}

final class FakeInstaller: UpdateInstalling, @unchecked Sendable {
    let canReplaceApp: Bool
    let failure: UpdateError?
    @MainActor private(set) var relaunched: URL?
    @MainActor private(set) var revealed: URL?

    init(canReplaceApp: Bool = true, failure: UpdateError? = nil) {
        self.canReplaceApp = canReplaceApp
        self.failure = failure
    }

    func download(_ release: AppRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        progress(0.5)
        progress(1)
        return URL(filePath: "/tmp/Sylvra.dmg")
    }

    func prepare(diskImage: URL) async throws -> URL {
        if let failure { throw failure }
        return URL(filePath: "/Applications/.Sylvra-update.app")
    }

    @MainActor func relaunch(with preparedApp: URL) { relaunched = preparedApp }
    @MainActor func reveal(diskImage: URL) { revealed = diskImage }
}

@MainActor
struct UpdateModelTests {
    static func release(_ version: String) -> AppRelease {
        AppRelease(
            version: ReleaseVersion(version) ?? ReleaseVersion(parts: [0]), notes: "- New",
            diskImage: URL(filePath: "/tmp/Sylvra-\(version).dmg"), diskImageSize: 1000)
    }

    static func defaults() -> UserDefaults {
        let name = "updates-tests-\(UUID().uuidString)"
        return UserDefaults(suiteName: name) ?? .standard
    }

    func model(
        _ fetcher: FakeFetcher, installer: FakeInstaller = FakeInstaller(), defaults: UserDefaults? = nil
    ) -> UpdateModel {
        UpdateModel(
            fetcher: fetcher, installer: installer, currentVersion: ReleaseVersion("0.5.35"), defaults: defaults)
    }

    @Test func automaticCheckAnnouncesANewerRelease() async {
        let model = model(FakeFetcher(release: Self.release("0.5.36")))
        await model.check(userInitiated: false)
        #expect(model.state == .available(Self.release("0.5.36")))
        #expect(model.isCardPresented)
    }

    @Test func automaticCheckStaysSilentWithoutUpdateOrOnError() async {
        let same = model(FakeFetcher(release: Self.release("0.5.35")))
        await same.check(userInitiated: false)
        #expect(same.state == .idle)
        #expect(!same.isCardPresented)

        let failing = model(FakeFetcher(error: UpdateError.server(500)))
        await failing.check(userInitiated: false)
        #expect(failing.state == .idle)
        #expect(!failing.isCardPresented)
    }

    @Test func checkForUpdatesAlwaysAnswers() async {
        let current = model(FakeFetcher(release: Self.release("0.5.35")))
        await current.check(userInitiated: true)
        #expect(current.state == .upToDate)
        #expect(current.isCardPresented)

        let failing = model(FakeFetcher(error: UpdateError.server(503)))
        await failing.check(userInitiated: true)
        guard case .failed(nil, _) = failing.state else {
            Issue.record("expected a failed check, got \(failing.state)")
            return
        }
        failing.later()
        #expect(failing.state == .idle)
        #expect(!failing.isCardPresented)
    }

    @Test func laterKeepsTheUpdateAndDoesNotPopUpAgainForTheSameRelease() async {
        let fetcher = FakeFetcher(release: Self.release("0.5.36"))
        let model = model(fetcher)
        await model.check(userInitiated: false)
        model.later()
        #expect(!model.isCardPresented)
        #expect(model.pendingRelease == Self.release("0.5.36"))

        await model.check(userInitiated: false)
        #expect(!model.isCardPresented)

        await fetcher.publish(Self.release("0.5.37"))
        await model.check(userInitiated: false)
        #expect(model.isCardPresented)
        #expect(model.pendingRelease == Self.release("0.5.37"))
    }

    @Test func skippedVersionIsOnlyAnnouncedWhenAsked() async {
        let defaults = Self.defaults()
        let fetcher = FakeFetcher(release: Self.release("0.5.36"))
        let model = model(fetcher, defaults: defaults)
        await model.check(userInitiated: false)
        model.skip()
        #expect(model.state == .idle)

        await model.check(userInitiated: false)
        #expect(!model.isCardPresented)

        await model.check(userInitiated: true)
        #expect(model.state == .available(Self.release("0.5.36")))

        await fetcher.publish(Self.release("0.5.37"))
        model.later()
        let fresh = self.model(fetcher, defaults: defaults)
        await fresh.check(userInitiated: false)
        #expect(fresh.pendingRelease == Self.release("0.5.37"))
    }

    @Test func automaticChecksCanBeTurnedOff() {
        let defaults = Self.defaults()
        let model = model(FakeFetcher(), defaults: defaults)
        #expect(model.automaticallyChecks)
        model.automaticallyChecks = false
        #expect(defaults.bool(forKey: UpdateModel.automaticKey) == false)
        #expect(defaults.object(forKey: "updates.automaticChecks") != nil)
    }

    @Test func installDownloadsVerifiesAndRelaunches() async {
        let installer = FakeInstaller()
        let model = model(FakeFetcher(release: Self.release("0.5.36")), installer: installer)
        await model.check(userInitiated: false)
        await model.install()
        #expect(model.state == .relaunching(Self.release("0.5.36")))
        #expect(installer.relaunched == URL(filePath: "/Applications/.Sylvra-update.app"))
    }

    @Test func appOutsideApplicationsGetsTheDiskImageShown() async {
        let installer = FakeInstaller(canReplaceApp: false)
        let model = model(FakeFetcher(release: Self.release("0.5.36")), installer: installer)
        await model.check(userInitiated: false)
        await model.install()
        #expect(model.state == .downloaded(Self.release("0.5.36")))
        #expect(installer.revealed == URL(filePath: "/tmp/Sylvra.dmg"))
        #expect(installer.relaunched == nil)
    }

    @Test func untrustedDownloadIsRefusedAndCanBeRetried() async {
        let installer = FakeInstaller(failure: .notTrusted("signed by another team"))
        let model = model(FakeFetcher(release: Self.release("0.5.36")), installer: installer)
        await model.check(userInitiated: false)
        await model.install()
        guard case .failed(.some(let release), let message) = model.state else {
            Issue.record("expected a failure, got \(model.state)")
            return
        }
        #expect(release == Self.release("0.5.36"))
        #expect(message.contains("Nothing was installed"))
        #expect(installer.relaunched == nil)
        #expect(model.pendingRelease == Self.release("0.5.36"))
    }
}
