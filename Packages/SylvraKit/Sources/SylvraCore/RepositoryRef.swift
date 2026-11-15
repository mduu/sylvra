import Foundation

/// A GitHub repository, optionally mapped to a local clone.
public struct RepositoryRef: Hashable, Sendable {
    public let owner: String
    public let name: String
    public var localClonePath: URL?

    public init(owner: String, name: String, localClonePath: URL? = nil) {
        self.owner = owner
        self.name = name
        self.localClonePath = localClonePath
    }

    /// `owner/name`, as used by GitHub.
    public var fullName: String { "\(owner)/\(name)" }
}
