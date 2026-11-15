import Foundation

/// Values available to a tool's placeholders. Paths of files and folders are relative to the checkout.
public struct ToolContext: Equatable, Sendable {
    /// Root of the PR checkout (review worktree or main clone).
    public var worktree: URL?
    /// Repository-relative path of the file the tool runs on.
    public var file: String?
    /// Repository-relative path of the folder (for file tools: the file's folder).
    public var folder: String?
    public var prNumber: Int?
    public var headSHA: String?
    public var baseSHA: String?

    public init(
        worktree: URL? = nil, file: String? = nil, folder: String? = nil, prNumber: Int? = nil,
        headSHA: String? = nil, baseSHA: String? = nil
    ) {
        self.worktree = worktree
        self.file = file
        self.folder = folder ?? file.map { ($0 as NSString).deletingLastPathComponent }
        self.prNumber = prNumber
        self.headSHA = headSHA
        self.baseSHA = baseSHA
    }

    /// The raw (unescaped) value of a placeholder name, or `nil` if it is not available.
    func value(of placeholder: CommandTemplate.Placeholder) -> String? {
        switch placeholder {
        case .file: file.map(absolute)
        case .folder: folder.map(absolute)
        case .repoRoot, .worktree: worktree?.path
        case .prNumber: prNumber.map(String.init)
        case .headSHA: headSHA.flatMap { $0.isEmpty ? nil : $0 }
        case .baseSHA: baseSHA.flatMap { $0.isEmpty ? nil : $0 }
        }
    }

    private func absolute(_ path: String) -> String {
        guard let worktree else { return path }
        return path.isEmpty ? worktree.path : worktree.appending(path: path).path
    }
}

/// Expands `{placeholder}`s in a custom tool command. Every substituted value is shell-escaped,
/// so paths and SHAs can never inject shell syntax; the template itself is the user's own command.
public enum CommandTemplate {
    public enum Placeholder: String, CaseIterable, Sendable {
        case file, folder, repoRoot, worktree, prNumber, headSHA, baseSHA

        public var token: String { "{\(rawValue)}" }
    }

    public enum ExpansionError: LocalizedError, Equatable {
        case missingValue(String)

        public var errorDescription: String? {
            switch self {
            case .missingValue(let token): String(localized: "\(token) is not available here.")
            }
        }
    }

    /// The command with all known placeholders replaced by shell-escaped values.
    /// Unknown `{…}` text is left alone (it may be shell brace expansion).
    public static func expand(_ template: String, context: ToolContext) throws -> String {
        var result = ""
        var rest = template[...]
        while let open = rest.firstIndex(of: "{") {
            result += rest[..<open]
            let afterOpen = rest.index(after: open)
            guard let close = rest[afterOpen...].firstIndex(of: "}"),
                let placeholder = Placeholder(rawValue: String(rest[afterOpen..<close]))
            else {
                result.append("{")
                rest = rest[afterOpen...]
                continue
            }
            guard let value = context.value(of: placeholder) else {
                throw ExpansionError.missingValue(placeholder.token)
            }
            result += ShellEscaping.quote(value)
            rest = rest[rest.index(after: close)...]
        }
        return result + rest
    }

    /// Placeholders used in `template`.
    public static func placeholders(in template: String) -> [Placeholder] {
        Placeholder.allCases.filter { template.contains($0.token) }
    }
}

/// POSIX shell quoting.
public enum ShellEscaping {
    /// `value` as a single shell word: wrapped in single quotes, embedded quotes as `'\''`.
    public static func quote(_ value: String) -> String {
        "'" + value.replacing("'", with: "'\\''") + "'"
    }
}
