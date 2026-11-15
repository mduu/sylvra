import Foundation

/// A user-defined shell command offered for files, folders or the whole pull request.
public struct CustomTool: Identifiable, Hashable, Codable, Sendable {
    public enum Scope: String, Codable, CaseIterable, Identifiable, Sendable {
        case file, folder, pullRequest

        public var id: String { rawValue }

        public var title: String {
            switch self {
            case .file: String(localized: "File")
            case .folder: String(localized: "Folder")
            case .pullRequest: String(localized: "Pull request")
            }
        }
    }

    public var id: UUID
    public var name: String
    public var scope: Scope
    /// Shell command with placeholders such as `{file}` (see `CommandTemplate`).
    public var command: String

    public init(id: UUID = UUID(), name: String, scope: Scope, command: String) {
        self.id = id
        self.name = name
        self.scope = scope
        self.command = command
    }

    /// Tools shown until the user edits the list.
    public static let examples: [CustomTool] = [
        CustomTool(name: "Run tests", scope: .pullRequest, command: "swift test"),
        CustomTool(name: "Open in Fork", scope: .pullRequest, command: "open -a Fork {repoRoot}"),
    ]
}
