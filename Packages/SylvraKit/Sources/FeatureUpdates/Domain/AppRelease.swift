import Foundation

/// A version number like `0.5.35` (a leading `v` is ignored); compared part by part, missing parts are 0.
public struct ReleaseVersion: Comparable, Hashable, Sendable, CustomStringConvertible {
    public let parts: [Int]

    public init?(_ text: String) {
        let trimmed = text.trimmingCharacters(in: .whitespaces)
        let number = trimmed.hasPrefix("v") || trimmed.hasPrefix("V") ? String(trimmed.dropFirst()) : trimmed
        let parts = number.split(separator: ".").map { Int($0) }
        guard !parts.isEmpty, parts.allSatisfy({ $0 != nil }) else { return nil }
        self.parts = parts.compactMap { $0 }
    }

    public init(parts: [Int]) {
        self.parts = parts
    }

    public var description: String { parts.map(String.init).joined(separator: ".") }

    public static func < (lhs: Self, rhs: Self) -> Bool {
        for index in 0..<max(lhs.parts.count, rhs.parts.count) {
            let left = index < lhs.parts.count ? lhs.parts[index] : 0
            let right = index < rhs.parts.count ? rhs.parts[index] : 0
            if left != right { return left < right }
        }
        return false
    }

    public static func == (lhs: Self, rhs: Self) -> Bool { !(lhs < rhs) && !(rhs < lhs) }

    public func hash(into hasher: inout Hasher) {
        var parts = parts
        while parts.last == 0 { parts.removeLast() }
        hasher.combine(parts)
    }
}

/// A published release of Sylvra with its disk image.
public struct AppRelease: Equatable, Sendable, Identifiable {
    public let version: ReleaseVersion
    /// What changed (the release's change list as Markdown).
    public let notes: String
    public let diskImage: URL
    public let diskImageSize: Int64
    public let page: URL?
    public let publishedAt: Date?

    public var id: String { version.description }

    public init(
        version: ReleaseVersion, notes: String, diskImage: URL, diskImageSize: Int64, page: URL? = nil,
        publishedAt: Date? = nil
    ) {
        self.version = version
        self.notes = notes
        self.diskImage = diskImage
        self.diskImageSize = diskImageSize
        self.page = page
        self.publishedAt = publishedAt
    }

    /// The change list of a release body written by `scripts/publish.sh` (install hints are for new users).
    static func changes(in body: String) -> String {
        let lines = body.components(separatedBy: .newlines)
        if let heading = lines.firstIndex(where: { $0.hasPrefix("## Changes") }) {
            let rest = lines[(heading + 1)...].prefix { !$0.hasPrefix("## ") }
            return rest.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
        }
        // No change list (e.g. the first release): everything but the install section.
        var kept: [String] = []
        var inInstall = false
        for line in lines {
            if line.hasPrefix("## ") { inInstall = line.hasPrefix("## Install") }
            if !inInstall { kept.append(line) }
        }
        return kept.joined(separator: "\n").trimmingCharacters(in: .whitespacesAndNewlines)
    }
}

/// GitHub's release JSON (`GET /repos/{owner}/{repo}/releases/latest`).
struct GitHubReleaseResponse: Decodable {
    struct Asset: Decodable {
        let name: String
        let size: Int64
        let browserDownloadURL: URL

        enum CodingKeys: String, CodingKey {
            case name, size
            case browserDownloadURL = "browser_download_url"
        }
    }

    let tagName: String
    let body: String?
    let htmlURL: URL?
    let draft: Bool
    let prerelease: Bool
    let publishedAt: Date?
    let assets: [Asset]

    enum CodingKeys: String, CodingKey {
        case body, draft, prerelease, assets
        case tagName = "tag_name"
        case htmlURL = "html_url"
        case publishedAt = "published_at"
    }

    /// A finished release with a disk image; drafts, pre-releases and releases without a DMG don't count.
    var release: AppRelease? {
        guard !draft, !prerelease, let version = ReleaseVersion(tagName),
            let image = assets.first(where: { $0.name.lowercased().hasSuffix(".dmg") })
        else { return nil }
        return AppRelease(
            version: version, notes: AppRelease.changes(in: body ?? ""), diskImage: image.browserDownloadURL,
            diskImageSize: image.size, page: htmlURL, publishedAt: publishedAt)
    }
}
