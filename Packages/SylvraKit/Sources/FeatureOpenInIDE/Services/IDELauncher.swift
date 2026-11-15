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
        let arguments = ide.launcherArguments(project: project, file: file, line: line)
        // Command line launchers (`rider`, `code`, `xed` scripts) hand over to the app and return.
        if let launcher = ide.launchers.lazy.compactMap(ExecutableLocator.locate).first {
            let result = try await runner.run(launcher, arguments: arguments, workingDirectory: directory)
            if result.exitCode == 0 { return }
        }
        guard let app = applicationURL(for: ide) else { throw IDELaunchError.notInstalled(ide.name) }
        let configuration = NSWorkspace.OpenConfiguration()
        configuration.activates = true
        if !ide.bundleLaunchers.isEmpty, !arguments.isEmpty {
            // Never wait for a bundle binary (it would stay in the foreground): let Launch Services start it.
            configuration.arguments = arguments
            _ = try await NSWorkspace.shared.openApplication(at: app, configuration: configuration)
        } else {
            _ = try await NSWorkspace.shared.open([project], withApplicationAt: app, configuration: configuration)
        }
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

public enum IDELaunchError: Error, LocalizedError, Equatable {
    case notInstalled(String)

    public var errorDescription: String? {
        switch self {
        case .notInstalled(let name): String(localized: "\(name) is not installed.")
        }
    }
}
