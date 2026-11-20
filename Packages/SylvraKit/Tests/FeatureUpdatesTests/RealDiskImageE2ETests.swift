import Foundation
import Testing

@testable import FeatureUpdates

/// Opt-in: the real installer on a real notarized disk image, e.g.
/// `SYLVRA_E2E_DMG=.build/release/Sylvra-0.5.35.dmg swift test --filter RealDiskImage` (codesign, spctl, hdiutil).
struct RealDiskImageE2ETests {
    @Test(.enabled(if: ProcessInfo.processInfo.environment["SYLVRA_E2E_DMG"] != nil))
    func preparesTheRealDiskImage() async throws {
        let dmg = URL(filePath: try #require(ProcessInfo.processInfo.environment["SYLVRA_E2E_DMG"]))
        let folder = FileManager.default.temporaryDirectory.appending(path: "e2e-\(UUID().uuidString)/Applications")
        try FileManager.default.createDirectory(at: folder, withIntermediateDirectories: true)
        let installer = SystemUpdateInstaller(appURL: folder.appending(path: "Sylvra.app"))
        let staged = try await installer.prepare(diskImage: dmg)
        print("E2E staged:", staged.path)
        #expect(FileManager.default.fileExists(atPath: staged.appending(path: "Contents/MacOS/Sylvra").path))
    }

    @Test(.enabled(if: ProcessInfo.processInfo.environment["SYLVRA_E2E_DMG"] != nil))
    func refusesAnUnsignedDiskImage() async throws {
        let folder = FileManager.default.temporaryDirectory.appending(path: "e2e-\(UUID().uuidString)")
        try FileManager.default.createDirectory(
            at: folder.appending(path: "Applications/content"), withIntermediateDirectories: true)
        let dmg = folder.appending(path: "fake.dmg")
        let process = Process()
        process.executableURL = URL(filePath: "/usr/bin/hdiutil")
        process.arguments = [
            "create", "-quiet", "-srcfolder", folder.appending(path: "Applications").path, "-format", "UDZO", dmg.path,
        ]
        try process.run()
        process.waitUntilExit()
        let installer = SystemUpdateInstaller(appURL: folder.appending(path: "Applications/Sylvra.app"))
        do {
            _ = try await installer.prepare(diskImage: dmg)
            Issue.record("an unsigned disk image was accepted")
        } catch let error as UpdateError {
            print("E2E refused:", error.localizedDescription)
            guard case .notTrusted = error else { Issue.record("wrong error \(error)"); return }
        }
    }
}
