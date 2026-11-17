import Foundation

/// Combined CI state of a commit (GitHub `statusCheckRollup`).
public enum CheckState: String, Sendable, Codable {
    case success, failure, pending, error, expected, none
}

/// Overall review decision of a pull request.
public enum ReviewDecision: String, Sendable, Codable {
    case approved = "APPROVED"
    case changesRequested = "CHANGES_REQUESTED"
    case reviewRequired = "REVIEW_REQUIRED"
    case none
}

/// Whether a pull request can be merged.
public enum Mergeability: String, Sendable, Codable {
    case mergeable = "MERGEABLE"
    case conflicting = "CONFLICTING"
    case unknown = "UNKNOWN"
}

/// Identifies a pull request across repositories.
public struct PullRequestID: Hashable, Sendable, Codable, CustomStringConvertible {
    public let owner: String
    public let repository: String
    public let number: Int

    public init(owner: String, repository: String, number: Int) {
        self.owner = owner
        self.repository = repository
        self.number = number
    }

    public var description: String { "\(owner)/\(repository)#\(number)" }

    /// Parses `owner/repository#number`.
    public init?(_ description: String) {
        let parts = description.split(separator: "#")
        let names = parts.first?.split(separator: "/") ?? []
        guard parts.count == 2, names.count == 2, let number = Int(parts[1]) else { return nil }
        self.init(owner: String(names[0]), repository: String(names[1]), number: number)
    }
}

/// The data needed to list a pull request (inbox row, header).
public struct PullRequestSummary: Identifiable, Hashable, Sendable, Codable {
    public let id: PullRequestID
    public let title: String
    public let author: UserRef
    public let url: URL?
    public let isDraft: Bool
    public let createdAt: Date
    public let updatedAt: Date
    public let additions: Int
    public let deletions: Int
    public let headRefName: String
    public let baseRefName: String
    public let checkState: CheckState
    public let reviewDecision: ReviewDecision
    public let mergeability: Mergeability
    /// The author is a GitHub App (bot account).
    public let authorIsBot: Bool
    /// Whether the signed-in reviewer acted last (`nil`: unknown, or the reviewer's own pull request).
    public let viewerActivity: ViewerActivity?
    /// Conversation comments plus code threads (`nil`: unknown).
    public let commentCount: Int?

    public init(
        id: PullRequestID,
        title: String,
        author: UserRef,
        url: URL? = nil,
        isDraft: Bool = false,
        createdAt: Date,
        updatedAt: Date,
        additions: Int,
        deletions: Int,
        headRefName: String,
        baseRefName: String,
        checkState: CheckState = .none,
        reviewDecision: ReviewDecision = .none,
        mergeability: Mergeability = .unknown,
        authorIsBot: Bool = false,
        viewerActivity: ViewerActivity? = nil,
        commentCount: Int? = nil
    ) {
        self.id = id
        self.title = title
        self.author = author
        self.url = url
        self.isDraft = isDraft
        self.createdAt = createdAt
        self.updatedAt = updatedAt
        self.additions = additions
        self.deletions = deletions
        self.headRefName = headRefName
        self.baseRefName = baseRefName
        self.checkState = checkState
        self.reviewDecision = reviewDecision
        self.mergeability = mergeability
        self.authorIsBot = authorIsBot
        self.viewerActivity = viewerActivity
        self.commentCount = commentCount
    }

    /// The reviewer already commented or reviewed and nothing happened since.
    public var isWaitingOnOthers: Bool { viewerActivity?.isWaitingOnOthers ?? false }

    /// Bot accounts: GitHub Apps and conventionally named service users (`dg-renovate`, `ci-bot`).
    public var isByBot: Bool {
        let login = author.login.lowercased()
        return authorIsBot || login.hasSuffix("[bot]") || login.hasSuffix("-bot")
            || ["renovate", "dependabot"].contains { login.contains($0) }
    }

    /// Changed lines in total.
    public var changedLines: Int { additions + deletions }

    /// T-shirt size of the change, as shown in the inbox.
    public var size: ChangeSize { ChangeSize(changedLines: changedLines) }
}

/// Rough size of a change.
public enum ChangeSize: String, Sendable, CaseIterable {
    case xs = "XS", s = "S", m = "M", l = "L", xl = "XL"

    public init(changedLines: Int) {
        switch changedLines {
        case ..<10: self = .xs
        case ..<100: self = .s
        case ..<400: self = .m
        case ..<1000: self = .l
        default: self = .xl
        }
    }
}

extension PullRequestSummary {
    /// The pull request on GitHub (falls back to github.com when the API gave no URL).
    public var webURL: URL? {
        url ?? URL(string: "https://github.com/\(id.owner)/\(id.repository)/pull/\(id.number)")
    }

    /// The repository on GitHub: the pull request URL without `/pull/<number>` (keeps GitHub Enterprise hosts).
    public var repositoryWebURL: URL? {
        if let url, url.pathComponents.suffix(2) == ["pull", String(id.number)],
            var components = URLComponents(url: url, resolvingAgainstBaseURL: false)
        {
            components.path = "/" + url.pathComponents.dropFirst().dropLast(2).joined(separator: "/")
            components.query = nil
            components.fragment = nil
            return components.url
        }
        return URL(string: "https://github.com/\(id.owner)/\(id.repository)")
    }
}
