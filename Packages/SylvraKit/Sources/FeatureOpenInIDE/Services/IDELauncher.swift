import AppKit
import Foundation
import Platform

/// Detects installed IDEs and opens projects in them.
public struct IDELauncher: Sendable {
    private let runner: any ProcessRunning

    public init(runner: any ProcessRunning = SystemProcessRunner()) {
        self.runner = runner
    }

    /// IDEs installed on this Mac (the default app is always available).
    @MainActor
    public func installedIDEs() -> [IDE] {
        IDE.all.filter { $0.kind == .defaultApp || applicationURL(for: $0) != nil }
    }

    @MainActor
    func applicationURL(for ide: IDE) -> URL? {
        ide.bundleIdentifiers.lazy.compactMap { NSWorkspace.shared.urlForApplication(withBundleIdentifier: $0) }.first
    }

    /// Opens `directory` (or the project file found in it) and optionally jumps to `file:line`.
    @MainActor
    public func open(_ ide: IDE, directory: URL, file: URL? = nil, line: Int? = nil) async throws {
        let project = ProjectDetector.project(in: directory, for: ide.kind)
        if ide.kind == .defaultApp {
            NSWorkspace.shared.open(file ?? project)
            return
        }
        if let launcher = launcher(for: ide) {
            let result = try await runner.run(
                launcher, arguments: ide.launcherArguments(project: project, file: file, line: line),
                workingDirectory: directory)
            if result.exitCode == 0 { return }
        }
        guard let app = applicationURL(for: ide) else { return }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        _ = try await NSWorkspace.shared.open([project], withApplicationAt: app, configuration: configuration)
    }

    @MainActor
    private func launcher(for ide: IDE) -> URL? {
        if let found = ide.launchers.lazy.compactMap(ExecutableLocator.locate).first { return found }
        guard let app = applicationURL(for: ide) else { return nil }
        return ide.bundleLaunchers.map { app.appending(path: $0) }
            .first { FileManager.default.isExecutableFile(atPath: $0.path) }
    }
}

/// Picks the file an IDE should open for a checkout (solution, workspace, project or the folder).
public enum ProjectDetector {
    public static func project(in directory: URL, for kind: IDE.Kind) -> URL {
        let entries = (try? FileManager.default.contentsOfDirectory(atPath: directory.path)) ?? []
        let preferred: [String] =
            switch kind {
            case .rider: ["slnx", "sln"]
            case .xcode: ["xcworkspace", "xcodeproj"]
            case .vsCode: ["code-workspace"]
            case .defaultApp: []
            }
        for ext in preferred {
            if let match = entries.sorted().first(where: { ($0 as NSString).pathExtension == ext }) {
                return directory.appending(path: match)
            }
        }
        return directory
    }
}
