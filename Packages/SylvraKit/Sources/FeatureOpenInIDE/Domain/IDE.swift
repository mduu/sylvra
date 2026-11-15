import Foundation

/// An editor or IDE Sylvra can open a checkout in (see specs/architecture.md §9).
public struct IDE: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case rider, vsCode, xcode, defaultApp
    }

    public var id: Kind { kind }
    public let kind: Kind
    public let name: String
    public let bundleIdentifiers: [String]
    /// Command line launcher names searched via `ExecutableLocator` (plus bundle-relative paths).
    public let launchers: [String]
    public let bundleLaunchers: [String]
    public let symbol: String

    public static let rider = IDE(
        kind: .rider, name: "Rider", bundleIdentifiers: ["com.jetbrains.rider", "com.jetbrains.rider-EAP"],
        launchers: ["rider"], bundleLaunchers: ["Contents/MacOS/rider"], symbol: "r.square")
    public static let vsCode = IDE(
        kind: .vsCode, name: "Visual Studio Code",
        bundleIdentifiers: ["com.microsoft.VSCode", "com.microsoft.VSCodeInsiders"],
        launchers: ["code"], bundleLaunchers: ["Contents/Resources/app/bin/code"],
        symbol: "chevron.left.forwardslash.chevron.right")
    public static let xcode = IDE(
        kind: .xcode, name: "Xcode", bundleIdentifiers: ["com.apple.dt.Xcode"], launchers: ["xed"], bundleLaunchers: [],
        symbol: "hammer")
    public static let defaultApp = IDE(
        kind: .defaultApp, name: String(localized: "Default App"), bundleIdentifiers: [], launchers: [],
        bundleLaunchers: [],
        symbol: "macwindow")

    public static let all: [IDE] = [.rider, .vsCode, .xcode, .defaultApp]

    /// Arguments for the command line launcher to open a project and optionally jump to a file and line.
    public func launcherArguments(project: URL, file: URL?, line: Int?) -> [String] {
        switch kind {
        case .rider:
            guard let file else { return [project.path] }
            return [project.path] + (line.map { ["--line", String($0)] } ?? []) + [file.path]
        case .vsCode:
            guard let file else { return [project.path] }
            return [project.path, "--goto", "\(file.path):\(line ?? 1)"]
        case .xcode:
            guard let file else { return [project.path] }
            return (line.map { ["--line", String($0)] } ?? []) + [file.path]
        case .defaultApp:
            return []
        }
    }
}

/// Where the PR head is checked out.
public enum CheckoutTarget: String, CaseIterable, Identifiable, Sendable {
    /// Sylvra-managed worktree; the user's working copy is never touched (default).
    case worktree
    /// The user's main local clone (explicit choice, e.g. projects that cannot run from a worktree).
    case mainClone

    public var id: String { rawValue }

    public var title: String {
        switch self {
        case .worktree: String(localized: "Review worktree")
        case .mainClone: String(localized: "Main clone")
        }
    }
}
