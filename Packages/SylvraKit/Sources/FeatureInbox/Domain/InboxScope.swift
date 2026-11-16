import Foundation

/// A repository the user added to the inbox.
public struct InboxRepository: Hashable, Sendable, Codable, Identifiable {
    public let owner: String
    public let name: String
    /// GitHub description, shown in search results only.
    public var summary: String?

    public init(owner: String, name: String, summary: String? = nil) {
        self.owner = owner
        self.name = name
        self.summary = summary
    }

    /// `owner/name`, as used by GitHub.
    public var fullName: String { "\(owner)/\(name)" }
    public var id: String { fullName.lowercased() }

    public static func == (lhs: Self, rhs: Self) -> Bool { lhs.id == rhs.id }
    public func hash(into hasher: inout Hasher) { hasher.combine(id) }
}

/// Which repositories the broad inbox sections search.
///
/// Accounts with access to large organizations don't want (and GitHub can't quickly search)
/// every repository, so the user picks the ones that matter. Empty means all repositories.
public struct InboxScope: Equatable, Sendable, Codable {
    public var repositories: [InboxRepository]

    public init(repositories: [InboxRepository] = []) {
        self.repositories = repositories
    }

    public static let all = InboxScope()

    public var isAll: Bool { repositories.isEmpty }

    public func contains(owner: String, name: String) -> Bool {
        repositories.contains(InboxRepository(owner: owner, name: name))
    }

    /// GitHub search queries for a section: one per chunk of repositories, so each query
    /// stays below GitHub's limit of 256 characters.
    func searchQueries(for section: InboxSection, now: Date = .now) -> [String] {
        let base = section.searchQuery(now: now)
        guard section.followsScope, !isAll else { return [base] }
        var queries: [String] = []
        var current = base
        for repository in repositories {
            let qualifier = " repo:\(repository.fullName)"
            if current != base, current.count + qualifier.count > Self.maxQueryLength {
                queries.append(current)
                current = base
            }
            current += qualifier
        }
        queries.append(current)
        return queries
    }

    static let maxQueryLength = 250
}

extension InboxSection {
    /// Sections limited to the chosen repositories. Review requests to you and your own
    /// pull requests always come from all repositories, so nothing addressed to you is missed.
    public var followsScope: Bool {
        switch self {
        case .myTeams, .involved, .recentlyClosed: true
        case .requestedFromMe, .myPullRequests: false
        }
    }
}
