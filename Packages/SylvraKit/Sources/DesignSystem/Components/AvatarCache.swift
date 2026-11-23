import AppKit
import CryptoKit
import ImageIO

/// Avatars, loaded and decoded once: in memory for the session, on disk across launches.
///
/// `AsyncImage` fetched and decoded every avatar again whenever a row was rebuilt (an inbox refresh, a scroll),
/// so they drew late and cost CPU. Here an avatar seen before shows in the same frame.
@MainActor
public final class AvatarCache {
    public static let shared = AvatarCache(store: AvatarStore(directory: AvatarStore.defaultDirectory))

    private let store: AvatarStore
    private var images: [URL: NSImage] = [:]
    /// Plenty for the people of a few organizations; beyond that the memory cache starts over.
    private let memoryLimit = 1_000

    init(store: AvatarStore) {
        self.store = store
    }

    /// The avatar when it was loaded in this session (no I/O).
    public func cachedImage(for url: URL) -> NSImage? { images[url] }

    /// The avatar from memory, disk or the network; `nil` when it can't be loaded.
    public func image(for url: URL) async -> NSImage? {
        if let image = images[url] { return image }
        guard let decoded = await store.image(for: url) else { return nil }
        let image = NSImage(cgImage: decoded.image, size: .zero)
        if images.count >= memoryLimit { images.removeAll() }
        images[url] = image
        return image
    }
}

/// Loads avatars off the main actor: from the disk cache when fresh, else from the network (kept on disk for
/// `maxAge`); decoded right away at a small size. Concurrent requests for one avatar share a single load.
public actor AvatarStore {
    public typealias Fetch = @Sendable (URL) async throws -> Data

    /// A decoded avatar (CGImage is immutable, so it crosses actors safely).
    public struct Decoded: @unchecked Sendable {
        public let image: CGImage
    }

    /// Enough for the largest avatar (32 pt) on a Retina screen.
    static let pixelSize = 128

    static var defaultDirectory: URL? {
        FileManager.default.urls(for: .cachesDirectory, in: .userDomainMask).first?
            .appending(path: "Avatars", directoryHint: .isDirectory)
    }

    private let directory: URL?
    private let maxAge: TimeInterval
    private let fetch: Fetch
    private var loading: [URL: Task<Decoded?, Never>] = [:]

    public init(
        directory: URL?, maxAge: TimeInterval = 7 * 86_400,
        fetch: @escaping Fetch = { url in try await URLSession.shared.data(from: url).0 }
    ) {
        self.directory = directory
        self.maxAge = maxAge
        self.fetch = fetch
    }

    public func image(for url: URL) async -> Decoded? {
        if let running = loading[url] { return await running.value }
        let task = Task { await load(url) }
        loading[url] = task
        let image = await task.value
        loading[url] = nil
        return image
    }

    private func load(_ url: URL) async -> Decoded? {
        let file = directory?.appending(path: Self.fileName(for: url))
        let cached = file.flatMap { try? Data(contentsOf: $0) }
        var data = cached
        if cached == nil || !isFresh(file) {
            if let fetched = try? await fetch(url), !fetched.isEmpty {
                data = fetched
                if let file { save(fetched, to: file) }
            }
            // Offline or rate-limited: an old avatar beats initials.
        }
        guard let data, let image = Self.decode(data) else { return nil }
        return Decoded(image: image)
    }

    private func isFresh(_ file: URL?) -> Bool {
        guard let file, let attributes = try? FileManager.default.attributesOfItem(atPath: file.path),
            let modified = attributes[.modificationDate] as? Date
        else { return false }
        return Date.now.timeIntervalSince(modified) < maxAge
    }

    private func save(_ data: Data, to file: URL) {
        try? FileManager.default.createDirectory(
            at: file.deletingLastPathComponent(), withIntermediateDirectories: true)
        try? data.write(to: file, options: .atomic)
    }

    /// A stable file name per URL (avatar URLs carry query parameters such as `?v=4`).
    static func fileName(for url: URL) -> String {
        SHA256.hash(data: Data(url.absoluteString.utf8)).map { String(format: "%02x", $0) }.joined()
    }

    /// Decodes and scales down in one step (a full-size avatar is 460 px).
    static func decode(_ data: Data) -> CGImage? {
        guard let source = CGImageSourceCreateWithData(data as CFData, nil) else { return nil }
        let options: [CFString: Any] = [
            kCGImageSourceCreateThumbnailFromImageAlways: true,
            kCGImageSourceCreateThumbnailWithTransform: true,
            kCGImageSourceThumbnailMaxPixelSize: pixelSize,
            kCGImageSourceShouldCacheImmediately: true,
        ]
        return CGImageSourceCreateThumbnailAtIndex(source, 0, options as CFDictionary)
    }
}
