import Foundation

/// Changed files as a folder hierarchy (tree view of the file navigator).
public struct FileTreeNode: Identifiable, Hashable, Sendable {
    /// Repository-relative path of the folder or file (`""` for the root).
    public let path: String
    /// Display name; compacted folder chains read like `Sources/Billing`.
    public let name: String
    public let file: FileDiff?
    public let children: [FileTreeNode]

    public var id: String { path }
    public var isFolder: Bool { file == nil }

    /// All files below (or the file itself).
    public var files: [FileDiff] { file.map { [$0] } ?? children.flatMap(\.files) }
    public var additions: Int { files.reduce(0) { $0 + $1.additions } }
    public var deletions: Int { files.reduce(0) { $0 + $1.deletions } }

    /// Builds the tree; folders first (alphabetically), then files, single-child folder chains compacted.
    public static func build(_ files: [FileDiff]) -> [FileTreeNode] {
        final class Folder {
            var folders: [String: Folder] = [:]
            var files: [FileDiff] = []
        }
        let root = Folder()
        for file in files {
            var folder = root
            for component in file.path.split(separator: "/").dropLast().map(String.init) {
                if folder.folders[component] == nil { folder.folders[component] = Folder() }
                if let next = folder.folders[component] { folder = next }
            }
            folder.files.append(file)
        }

        func nodes(_ folder: Folder, parentPath: String) -> [FileTreeNode] {
            let subfolders = folder.folders.keys.sorted { $0.localizedStandardCompare($1) == .orderedAscending }
                .compactMap { name -> FileTreeNode? in
                    guard var current = folder.folders[name] else { return nil }
                    var displayName = name
                    var path = parentPath.isEmpty ? name : "\(parentPath)/\(name)"
                    // Compact chains like Sources → Billing into "Sources/Billing".
                    while current.files.isEmpty, current.folders.count == 1,
                        let (childName, child) = current.folders.first
                    {
                        displayName += "/\(childName)"
                        path += "/\(childName)"
                        current = child
                    }
                    return FileTreeNode(
                        path: path, name: displayName, file: nil, children: nodes(current, parentPath: path))
                }
            let leafs = folder.files.sorted { $0.fileName.localizedStandardCompare($1.fileName) == .orderedAscending }
                .map { FileTreeNode(path: $0.path, name: $0.fileName, file: $0, children: []) }
            return subfolders + leafs
        }
        return nodes(root, parentPath: "")
    }
}
