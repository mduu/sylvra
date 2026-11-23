import AppKit
import Foundation
import Testing

@testable import DesignSystem

struct AvatarStoreTests {
    private let url = URL(string: "https://avatars.githubusercontent.com/u/42?v=4")!

    /// A 200 × 200 PNG, larger than avatars are kept.
    static let png: Data = {
        let image = NSImage(size: NSSize(width: 200, height: 200), flipped: false) { rect in
            NSColor.systemPurple.setFill()
            rect.fill()
            return true
        }
        let rep = NSBitmapImageRep(data: image.tiffRepresentation ?? Data())
        return rep?.representation(using: .png, properties: [:]) ?? Data()
    }()

    /// Counts network loads; can fail them (offline).
    actor Network {
        var loads = 0
        var isOffline = false
        func load() throws -> Data {
            loads += 1
            if isOffline { throw URLError(.notConnectedToInternet) }
            return AvatarStoreTests.png
        }
        func goOffline() { isOffline = true }
    }

    private func directory() -> URL {
        FileManager.default.temporaryDirectory.appending(path: "AvatarStoreTests-\(UUID().uuidString)")
    }

    @Test func loadsOnceAndScalesDown() async throws {
        let network = Network()
        let store = AvatarStore(directory: directory()) { _ in try await network.load() }
        async let first = store.image(for: url)
        async let second = store.image(for: url)
        let images = await [first, second]
        #expect(await network.loads == 1)
        let image = try #require(images[0]?.image)
        #expect(max(image.width, image.height) <= AvatarStore.pixelSize)
    }

    @Test func aNewLaunchTakesTheAvatarFromDisk() async {
        let folder = directory()
        let network = Network()
        _ = await AvatarStore(directory: folder) { _ in try await network.load() }.image(for: url)
        let relaunched = AvatarStore(directory: folder) { _ in try await network.load() }
        #expect(await relaunched.image(for: url) != nil)
        #expect(await network.loads == 1)
    }

    @Test func reloadsAStaleAvatarAndKeepsItWhenOffline() async {
        let folder = directory()
        let network = Network()
        _ = await AvatarStore(directory: folder) { _ in try await network.load() }.image(for: url)
        await network.goOffline()
        // maxAge 0: every avatar on disk is stale.
        let stale = AvatarStore(directory: folder, maxAge: 0) { _ in try await network.load() }
        #expect(await stale.image(for: url) != nil)
        #expect(await network.loads == 2)
    }

    @Test func fileNamesAreStablePerURL() {
        #expect(AvatarStore.fileName(for: url) == AvatarStore.fileName(for: url))
        let other = URL(string: "https://avatars.githubusercontent.com/u/43?v=4")!
        #expect(AvatarStore.fileName(for: url) != AvatarStore.fileName(for: other))
    }
}
