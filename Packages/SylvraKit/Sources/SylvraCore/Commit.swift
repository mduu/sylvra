import Foundation

/// A commit of a pull request.
public struct Commit: Identifiable, Hashable, Sendable {
    public var id: String { sha }
    public let sha: String
    public let subject: String
    public let body: String
    public let author: UserRef
    public let authoredAt: Date
    public let isVerified: Bool
    public let checkState: CheckState
    public let url: URL?

    public init(
        sha: String,
        subject: String,
        body: String = "",
        author: UserRef,
        authoredAt: Date,
        isVerified: Bool = false,
        checkState: CheckState = .none,
        url: URL? = nil
    ) {
        self.sha = sha
        self.subject = subject
        self.body = body
        self.author = author
        self.authoredAt = authoredAt
        self.isVerified = isVerified
        self.checkState = checkState
        self.url = url
    }

    /// The 7-character abbreviation shown in the UI.
    public var shortSHA: String { String(sha.prefix(7)) }
}
