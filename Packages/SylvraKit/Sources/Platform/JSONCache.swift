import Foundation

/// Small on-disk cache for codable values (inbox snapshot, AI review results).
///
/// Files live in `~/Library/Application Support/Sylvra/cache/<key>.json`. Reads and writes never throw to the
/// caller: a broken cache simply behaves like an empty one.
public struct JSONCache: Sendable {
    private let directory: URL

    public init(directory: URL? = nil) {
        let support =
            FileManager.default.urls(for: .applicationSupportDirectory, in: .userDomainMask).first
            ?? FileManager.default.homeDirectoryForCurrentUser.appending(path: "Library/Application Support")
        self.directory = directory ?? support.appending(path: "Sylvra/cache", directoryHint: .isDirectory)
    }

    public func load<Value: Decodable>(_ type: Value.Type, key: String) -> Value? {
        guard let data = try? Data(contentsOf: url(for: key)) else { return nil }
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try? decoder.decode(type, from: data)
    }

    public func save(_ value: some Encodable, key: String) {
        let encoder = JSONEncoder()
        encoder.dateEncodingStrategy = .iso8601
        guard let data = try? encoder.encode(value) else { return }
        try? FileManager.default.createDirectory(at: directory, withIntermediateDirectories: true)
        try? data.write(to: url(for: key), options: .atomic)
    }

    /// Encodes and writes on a background queue (in order), so a refresh never waits for the disk.
    public func saveInBackground(_ value: some Encodable & Sendable, key: String) {
        Self.writes.async { save(value, key: key) }
    }

    /// Returns once the background writes queued so far are on disk (tests, before quitting).
    public static func waitForWrites() async {
        await withCheckedContinuation { continuation in writes.async { continuation.resume() } }
    }

    private static let writes = DispatchQueue(label: "Sylvra.JSONCache", qos: .utility)

    private func url(for key: String) -> URL {
        let safe = key.map { $0.isLetter || $0.isNumber || $0 == "-" ? $0 : "_" }
        return directory.appending(path: String(safe) + ".json")
    }
}
