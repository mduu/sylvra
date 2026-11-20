import AppKit
import Foundation
import Platform

/// Downloads, verifies and installs a release; separate so the update flow can be tested without touching the app.
public protocol UpdateInstalling: Sendable {
    /// Whether the running app can be replaced in place (it lives in a writable Applications folder).
    var canReplaceApp: Bool { get }
    /// Downloads the disk image; `progress` gets the fraction done (0…1).
    func download(_ release: AppRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> URL
    /// Checks the app in the disk image and puts it next to the running app, ready to swap.
    func prepare(diskImage: URL) async throws -> URL
    /// Quits Sylvra, swaps in the prepared app and opens it.
    @MainActor func relaunch(with preparedApp: URL)
    /// Shows the disk image in the Finder (when the app can't be replaced in place).
    @MainActor func reveal(diskImage: URL)
}

/// The real installer: `hdiutil`, `codesign`, `spctl` and `ditto`, all with argument arrays.
public struct SystemUpdateInstaller: UpdateInstalling {
    /// Releases are signed by this Developer ID team; anything else is refused.
    public static let teamIdentifier = "UYT5K989XD"

    private let runner: any ProcessRunning
    private let appURL: URL

    public init(runner: any ProcessRunning = SystemProcessRunner(), appURL: URL = Bundle.main.bundleURL) {
        self.runner = runner
        self.appURL = appURL
    }

    public var canReplaceApp: Bool {
        let folder = appURL.deletingLastPathComponent()
        // Not a development build (Xcode's DerivedData) or an app started from the disk image.
        return folder.lastPathComponent == "Applications"
            && FileManager.default.isWritableFile(atPath: folder.path)
    }

    public func download(_ release: AppRelease, progress: @escaping @Sendable (Double) -> Void) async throws -> URL {
        let delegate = DownloadProgress(expected: release.diskImageSize, report: progress)
        let (location, response): (URL, URLResponse)
        do {
            (location, response) = try await URLSession.shared.download(from: release.diskImage, delegate: delegate)
        } catch {
            throw UpdateError.download(error.localizedDescription)
        }
        guard let status = (response as? HTTPURLResponse)?.statusCode, (200..<300).contains(status) else {
            throw UpdateError.download(String(localized: "unexpected answer"))
        }
        let target = FileManager.default.temporaryDirectory
            .appending(path: "Sylvra-\(release.version).dmg")
        try? FileManager.default.removeItem(at: target)
        try FileManager.default.moveItem(at: location, to: target)
        progress(1)
        return target
    }

    public func prepare(diskImage: URL) async throws -> URL {
        // The disk image itself must be notarized (stapled) and come from our team.
        try await verify(diskImage, type: "open", context: "context:primary-signature")
        let mount = FileManager.default.temporaryDirectory.appending(path: "Sylvra-update-\(UUID().uuidString)")
        try FileManager.default.createDirectory(at: mount, withIntermediateDirectories: true)
        try await run(
            "/usr/bin/hdiutil",
            ["attach", diskImage.path, "-nobrowse", "-readonly", "-noautoopen", "-mountpoint", mount.path],
            failure: { UpdateError.install(String(localized: "couldn't open the disk image (\($0))")) })
        defer {
            let runner = runner
            Task.detached {
                _ = try? await runner.run(
                    URL(filePath: "/usr/bin/hdiutil"), arguments: ["detach", mount.path, "-force"],
                    workingDirectory: nil)
            }
        }
        guard
            let app = try FileManager.default.contentsOfDirectory(at: mount, includingPropertiesForKeys: nil)
                .first(where: { $0.pathExtension == "app" })
        else { throw UpdateError.install(String(localized: "no app in the disk image")) }
        try await verify(app, type: "execute", context: nil)
        guard try await teamIdentifier(of: app) == Self.teamIdentifier else {
            throw UpdateError.notTrusted(String(localized: "signed by another team"))
        }
        // Next to the running app (same volume), so the swap is a rename.
        let staged = appURL.deletingLastPathComponent().appending(path: ".Sylvra-update-\(UUID().uuidString).app")
        try await run(
            "/usr/bin/ditto", [app.path, staged.path],
            failure: { UpdateError.install(String(localized: "couldn't copy the new version (\($0))")) })
        return staged
    }

    /// Waits for Sylvra (`$1`) to quit, swaps the staged app (`$2`) in for the target (`$3`) — the old one comes
    /// back if anything fails — and opens it. Arguments only; nothing from the release goes into the script text.
    static let swapScript = """
        pid="$1"; staged="$2"; target="$3"; backup="$3.previous"
        while kill -0 "$pid" 2>/dev/null; do sleep 0.2; done
        rm -rf "$backup"
        if mv "$target" "$backup" && mv "$staged" "$target"; then
          rm -rf "$backup"
        else
          [ -d "$target" ] || mv "$backup" "$target"
          rm -rf "$staged"
        fi
        open "$target"
        """

    @MainActor public func relaunch(with preparedApp: URL) {
        let process = Process()
        process.executableURL = URL(filePath: "/bin/sh")
        process.arguments = [
            "-c", Self.swapScript, "sylvra-update", String(ProcessInfo.processInfo.processIdentifier), preparedApp.path,
            appURL.path,
        ]
        do {
            try process.run()
        } catch {
            return
        }
        NSApplication.shared.terminate(nil)
    }

    @MainActor public func reveal(diskImage: URL) {
        NSWorkspace.shared.open(diskImage)
    }

    // MARK: Checks

    /// Gatekeeper's verdict: signed with a Developer ID and notarized.
    private func verify(_ url: URL, type: String, context: String?) async throws {
        try await run(
            "/usr/bin/codesign", ["--verify", "--deep", "--strict", url.path],
            failure: { UpdateError.notTrusted(String(localized: "invalid signature: \($0)")) })
        var arguments = ["--assess", "--type", type]
        if let context { arguments += ["--context", context] }
        try await run(
            "/usr/sbin/spctl", arguments + [url.path],
            failure: { UpdateError.notTrusted(String(localized: "not notarized: \($0)")) })
    }

    private func teamIdentifier(of app: URL) async throws -> String? {
        let result = try await runner.run(
            URL(filePath: "/usr/bin/codesign"), arguments: ["-dv", "--verbose=2", app.path], workingDirectory: nil)
        // codesign prints the details to standard error.
        return (result.standardError + result.standardOutput).components(separatedBy: .newlines)
            .first { $0.hasPrefix("TeamIdentifier=") }
            .map { String($0.dropFirst("TeamIdentifier=".count)) }
    }

    @discardableResult
    private func run(_ tool: String, _ arguments: [String], failure: (String) -> UpdateError) async throws
        -> ProcessResult
    {
        let result: ProcessResult
        do {
            result = try await runner.run(URL(filePath: tool), arguments: arguments, workingDirectory: nil)
        } catch {
            throw failure(error.localizedDescription)
        }
        guard result.exitCode == 0 else {
            throw failure(result.standardError.trimmingCharacters(in: .whitespacesAndNewlines))
        }
        return result
    }
}

/// Reports download progress of one task.
private final class DownloadProgress: NSObject, URLSessionDownloadDelegate, Sendable {
    private let expected: Int64
    private let report: @Sendable (Double) -> Void

    init(expected: Int64, report: @escaping @Sendable (Double) -> Void) {
        self.expected = expected
        self.report = report
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didWriteData bytesWritten: Int64,
        totalBytesWritten: Int64, totalBytesExpectedToWrite: Int64
    ) {
        let total = totalBytesExpectedToWrite > 0 ? totalBytesExpectedToWrite : expected
        guard total > 0 else { return }
        report(min(Double(totalBytesWritten) / Double(total), 1))
    }

    func urlSession(
        _ session: URLSession, downloadTask: URLSessionDownloadTask, didFinishDownloadingTo location: URL
    ) {}
}
