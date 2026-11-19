import Foundation

/// Where Sylvra looks for the user's clones (per Mac, in UserDefaults), so it never clones a repository twice.
public struct RepositorySearchSettings: Codable, Equatable, Sendable {
    /// Folders searched first, in this order, up to three levels deep.
    public var folders: [String]
    /// Spotlight search in the home folder when the folders don't contain the repository.
    public var usesSpotlight: Bool

    public init(folders: [String], usesSpotlight: Bool = true) {
        self.folders = folders
        self.usesSpotlight = usesSpotlight
    }

    public var folderURLs: [URL] { folders.map { URL(fileURLWithPath: $0) } }

    static let key = "repositories.search"

    /// The saved settings, or the suggested folders on first use.
    public static func load(from defaults: UserDefaults = .standard) -> Self {
        guard let data = defaults.data(forKey: key), let saved = try? JSONDecoder().decode(Self.self, from: data)
        else { return Self(folders: suggestedFolders().map(\.path)) }
        return saved
    }

    public func save(to defaults: UserDefaults = .standard) {
        guard let data = try? JSONEncoder().encode(self) else { return }
        defaults.set(data, forKey: Self.key)
    }

    /// Typical names of folders with repositories, compared case-insensitively (`~/Dev` and `~/dev`).
    static let typicalNames: Set<String> = [
        "dev", "developer", "development", "projects", "code", "src", "source", "repos", "repositories", "git",
        "github", "workspace", "workspaces", "work",
    ]

    /// Existing folders in `home` (and `home/Documents`) with a typical name, spelled as on disk.
    public static func suggestedFolders(
        in home: URL = FileManager.default.homeDirectoryForCurrentUser
    ) -> [URL] {
        let parents = [home, home.appending(path: "Documents")]
        return parents.flatMap { parent in
            let names = (try? FileManager.default.contentsOfDirectory(atPath: parent.path)) ?? []
            return names.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .filter { typicalNames.contains($0.lowercased()) }
                .map { parent.appending(path: $0) }
                .filter { url in
                    var isDirectory: ObjCBool = false
                    return FileManager.default.fileExists(atPath: url.path, isDirectory: &isDirectory)
                        && isDirectory.boolValue
                }
        }
    }
}
