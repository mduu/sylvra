import Foundation

/// A GitHub user as shown in the UI (author, reviewer, committer).
public struct UserRef: Hashable, Sendable {
    public let login: String
    public let name: String?
    public let avatarURL: URL?

    public init(login: String, name: String? = nil, avatarURL: URL? = nil) {
        self.login = login
        self.name = name
        self.avatarURL = avatarURL
    }

    /// Display name, falling back to the login.
    public var displayName: String { name ?? login }

    /// Up to two initials, used as avatar fallback.
    public var initials: String {
        let words = displayName.split(whereSeparator: { $0 == " " || $0 == "-" || $0 == "_" })
        let letters = words.prefix(2).compactMap(\.first)
        return String(letters).uppercased()
    }
}
