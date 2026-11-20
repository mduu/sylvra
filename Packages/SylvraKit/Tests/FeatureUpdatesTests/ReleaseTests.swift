import Foundation
import Testing

@testable import FeatureUpdates

struct ReleaseVersionTests {
    @Test func comparesPartByPart() throws {
        let older = try #require(ReleaseVersion("0.5.35"))
        let newer = try #require(ReleaseVersion("v0.5.36"))
        #expect(older < newer)
        #expect(try #require(ReleaseVersion("0.10.0")) > newer)
        #expect(try #require(ReleaseVersion("1.0")) == ReleaseVersion("1.0.0"))
        #expect(Set([ReleaseVersion("1.0"), ReleaseVersion("1.0.0")]).count == 1)
    }

    @Test func rejectsTextThatIsNoVersion() {
        #expect(ReleaseVersion("nightly") == nil)
        #expect(ReleaseVersion("1.2-beta") == nil)
        #expect(ReleaseVersion("") == nil)
    }
}

struct ReleaseDecodingTests {
    static func json(
        tag: String = "v0.5.36", draft: Bool = false, prerelease: Bool = false, asset: String = "Sylvra-0.5.36.dmg"
    )
        -> Data
    {
        Data(
            """
            {"tag_name": "\(tag)", "draft": \(draft), "prerelease": \(prerelease),
             "html_url": "https://github.com/mduu/sylvra/releases/tag/\(tag)",
             "published_at": "2026-11-20T08:00:00Z",
             "body": "## Install\\nOpen the disk image.\\n\\n## Changes since v0.5.35\\n- Auto-update\\n- Faster diff\\n\\n## Notes\\nx",
             "assets": [{"name": "\(asset)", "size": 18400000,
                         "browser_download_url": "https://github.com/mduu/sylvra/releases/download/\(tag)/\(asset)"}]}
            """.utf8)
    }

    @Test func readsTheReleaseWithItsDiskImageAndChanges() throws {
        let release = try #require(try GitHubReleaseFetcher.decode(Self.json()))
        #expect(release.version == ReleaseVersion("0.5.36"))
        #expect(release.notes == "- Auto-update\n- Faster diff")
        #expect(release.diskImage.lastPathComponent == "Sylvra-0.5.36.dmg")
        #expect(release.diskImageSize == 18_400_000)
        #expect(release.publishedAt != nil)
    }

    @Test func ignoresDraftsPrereleasesAndReleasesWithoutDiskImage() throws {
        #expect(try GitHubReleaseFetcher.decode(Self.json(draft: true)) == nil)
        #expect(try GitHubReleaseFetcher.decode(Self.json(prerelease: true)) == nil)
        #expect(try GitHubReleaseFetcher.decode(Self.json(asset: "Sylvra.zip")) == nil)
        #expect(try GitHubReleaseFetcher.decode(Self.json(tag: "latest")) == nil)
    }

    @Test func keepsABodyWithoutChangesHeading() {
        #expect(AppRelease.changes(in: "  - One fix\n") == "- One fix")
    }

    @Test func dropsTheInstallSectionWithoutChangeList() {
        let body = "## Install\n\nDrag Sylvra into Applications.\n\n## Highlights\n- Inbox\n- AI review"
        #expect(AppRelease.changes(in: body) == "## Highlights\n- Inbox\n- AI review")
    }
}
