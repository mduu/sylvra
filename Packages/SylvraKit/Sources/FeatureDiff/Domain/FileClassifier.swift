import Foundation

/// What a changed file is — used to collapse noise (see specs/projectidea.md §5.3).
public enum FileKind: String, Sendable, CaseIterable {
    case source, test, config, generated, lockfile, asset, docs

    /// Noise is collapsed at the bottom of the file list by default.
    public var isNoise: Bool { self == .generated || self == .lockfile }
}

public enum FileClassifier {
    private static let lockfiles: Set<String> = [
        "package-lock.json", "yarn.lock", "pnpm-lock.yaml", "Package.resolved", "Podfile.lock", "Gemfile.lock",
        "Cargo.lock", "composer.lock", "poetry.lock", "packages.lock.json", "go.sum", "bun.lockb", "uv.lock",
    ]
    private static let assetExtensions: Set<String> = [
        "png", "jpg", "jpeg", "gif", "svg", "webp", "ico", "pdf", "ttf", "otf", "woff", "woff2", "mp4", "mov", "mp3",
    ]
    private static let docExtensions: Set<String> = ["md", "markdown", "rst", "txt", "adoc"]
    private static let configExtensions: Set<String> = [
        "json", "yml", "yaml", "toml", "xml", "plist", "ini", "cfg", "conf", "xcconfig", "props", "targets",
        "editorconfig",
    ]

    public static func classify(_ path: String) -> FileKind {
        let name = (path as NSString).lastPathComponent
        let lowerPath = path.lowercased()
        let ext = (name as NSString).pathExtension.lowercased()

        if lockfiles.contains(name) { return .lockfile }
        if isGenerated(lowerPath, name: name) { return .generated }
        if isTest(lowerPath, name: name) { return .test }
        if assetExtensions.contains(ext) || lowerPath.contains(".xcassets/") { return .asset }
        if docExtensions.contains(ext) || lowerPath.hasPrefix("docs/") { return .docs }
        if configExtensions.contains(ext) || name.hasPrefix(".") || lowerPath.hasPrefix(".github/")
            || name == "Dockerfile" || name == "Makefile" || name.hasSuffix(".pbxproj") || name.hasSuffix(".csproj")
        {
            return .config
        }
        return .source
    }

    private static func isGenerated(_ lowerPath: String, name: String) -> Bool {
        let markers = [
            ".generated.", ".g.cs", ".designer.cs", ".pb.", "_pb2.py", ".min.js", ".min.css", "/generated/",
            "/__snapshots__/",
            ".snap",
        ]
        return markers.contains { lowerPath.contains($0) } || lowerPath.hasPrefix("generated/")
    }

    private static func isTest(_ lowerPath: String, name: String) -> Bool {
        let lowerName = name.lowercased()
        let stem = (lowerName as NSString).deletingPathExtension
        return lowerPath.contains("/tests/") || lowerPath.hasPrefix("tests/") || lowerPath.contains("/test/")
            || lowerPath.hasPrefix("test/") || lowerPath.contains("__tests__") || stem.hasSuffix("tests")
            || stem.hasSuffix("test") || stem.hasSuffix("spec") || lowerName.contains(".test.")
            || lowerName.contains(".spec.")
            || lowerName.hasPrefix("test_")
    }
}
