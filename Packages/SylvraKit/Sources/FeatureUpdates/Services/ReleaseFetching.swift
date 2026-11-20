import Foundation

/// Where new versions come from.
public protocol ReleaseFetching: Sendable {
    /// The newest finished release (`nil`: none with a disk image).
    func latestRelease() async throws -> AppRelease?
}

/// Sylvra's public GitHub releases; no token needed (60 requests an hour per address are plenty).
public struct GitHubReleaseFetcher: ReleaseFetching {
    public static let repository = "mduu/sylvra"
    private let session: URLSession

    public init(session: URLSession = .shared) {
        self.session = session
    }

    public func latestRelease() async throws -> AppRelease? {
        guard let url = URL(string: "https://api.github.com/repos/\(Self.repository)/releases/latest") else {
            return nil
        }
        var request = URLRequest(url: url, cachePolicy: .reloadIgnoringLocalCacheData, timeoutInterval: 20)
        request.setValue("application/vnd.github+json", forHTTPHeaderField: "Accept")
        request.setValue("Sylvra-Updater", forHTTPHeaderField: "User-Agent")
        let (data, response) = try await session.data(for: request)
        let status = (response as? HTTPURLResponse)?.statusCode ?? 0
        if status == 404 { return nil }  // no release published yet
        guard (200..<300).contains(status) else { throw UpdateError.server(status) }
        return try Self.decode(data)
    }

    static func decode(_ data: Data) throws -> AppRelease? {
        let decoder = JSONDecoder()
        decoder.dateDecodingStrategy = .iso8601
        return try decoder.decode(GitHubReleaseResponse.self, from: data).release
    }
}

/// Why an update didn't go through (shown in the update card).
public enum UpdateError: Error, Equatable, Sendable, LocalizedError {
    case server(Int)
    case download(String)
    case notTrusted(String)
    case install(String)

    public var errorDescription: String? {
        switch self {
        case .server(let status): String(localized: "GitHub answered with status \(status).")
        case .download(let reason): String(localized: "The download failed: \(reason)")
        case .notTrusted(let reason):
            String(localized: "The download isn't a genuine, notarized Sylvra (\(reason)). Nothing was installed.")
        case .install(let reason): String(localized: "Installing failed: \(reason)")
        }
    }
}
