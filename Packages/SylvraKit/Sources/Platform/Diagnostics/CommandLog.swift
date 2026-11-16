import Foundation
import Observation

/// One GitHub request or external command Sylvra ran (shown in the Commands panel).
public struct CommandLogEntry: Identifiable, Hashable, Sendable {
    public enum Kind: String, Sendable, CaseIterable {
        case github, git, process
    }

    public let id = UUID()
    public let kind: Kind
    /// Short title, e.g. `GraphQL search`, `GET /repos/acme/billing/pulls/1/files`, `git worktree add …`.
    public let title: String
    public let startedAt: Date
    public let duration: TimeInterval
    /// `200`, `exit 0`, `failed` …
    public let status: String
    public let isFailure: Bool
    /// Request details (GraphQL variables, arguments); never tokens.
    public let request: String?
    /// A short preview of the answer, or only its size when it contains code or secrets.
    public let response: String?

    public init(
        kind: Kind, title: String, startedAt: Date, duration: TimeInterval, status: String, isFailure: Bool,
        request: String? = nil, response: String? = nil
    ) {
        self.kind = kind
        self.title = title
        self.startedAt = startedAt
        self.duration = duration
        self.status = status
        self.isFailure = isFailure
        self.request = request
        self.response = response
    }
}

/// The GitHub requests and commands of this app session, newest last (in memory only, never written to disk).
@MainActor @Observable
public final class CommandLog {
    public static let shared = CommandLog()

    /// Most recent entries, at most `limit`.
    public private(set) var entries: [CommandLogEntry] = []
    public let limit: Int

    public init(limit: Int = 500) {
        self.limit = limit
    }

    public func append(_ entry: CommandLogEntry) {
        entries.append(entry)
        if entries.count > limit { entries.removeFirst(entries.count - limit) }
    }

    public func clear() {
        entries = []
    }

    /// Records from any thread into the shared log.
    public nonisolated static func record(_ entry: CommandLogEntry) {
        Task { @MainActor in shared.append(entry) }
    }
}

/// Builds the request and response texts of log entries without leaking secrets or code.
public enum CommandLogText {
    static let previewLimit = 2_000
    static let argumentLimit = 200

    /// JSON answers indented for reading (small ones only), then shortened like any text.
    public static func jsonPreview(_ data: Data) -> String {
        guard data.count < 500_000, let object = try? JSONSerialization.jsonObject(with: data),
            let pretty = try? JSONSerialization.data(
                withJSONObject: object, options: [.prettyPrinted, .sortedKeys, .withoutEscapingSlashes])
        else { return preview(data) }
        return preview(String(decoding: pretty, as: UTF8.self), byteCount: data.count)
    }

    /// The first `previewLimit` characters of a text answer.
    public static func preview(_ data: Data) -> String {
        preview(String(decoding: data.prefix(previewLimit * 4), as: UTF8.self), byteCount: data.count)
    }

    public static func preview(_ text: String, byteCount: Int? = nil) -> String {
        let size = byteCount ?? text.utf8.count
        guard text.count > previewLimit else { return text }
        return String(text.prefix(previewLimit)) + "\n… (\(size.formatted(.byteCount(style: .file))) in total)"
    }

    /// Only the size: for answers that contain code (diffs, file contents) or secrets.
    public static func sizeOnly(_ byteCount: Int, reason: String) -> String {
        "\(byteCount.formatted(.byteCount(style: .file))) — \(reason)"
    }

    /// Arguments as a command line, each shortened (prompts can be long).
    public static func commandLine(_ executable: String, _ arguments: [String]) -> String {
        ([executable] + arguments.map(shortened)).joined(separator: " ")
    }

    static func shortened(_ argument: String) -> String {
        let single = argument.replacingOccurrences(of: "\n", with: " ")
        let quoted = single.contains(" ") ? "\"\(single)\"" : single
        guard quoted.count > argumentLimit else { return quoted }
        return String(quoted.prefix(argumentLimit)) + "…"
    }

    /// The top-level fields of a GraphQL document, e.g. `query search` or `query repository, viewer`.
    public static func graphQLOperation(_ query: String) -> String {
        let trimmed = query.trimmingCharacters(in: .whitespacesAndNewlines)
        let kind = trimmed.hasPrefix("mutation") ? "mutation" : "query"
        guard let open = trimmed.firstIndex(of: "{") else { return kind }
        var fields: [String] = []
        var scanner = FieldScanner()
        for character in trimmed[open...] {
            if let field = scanner.feed(character), !fields.contains(field), fields.count < 4 { fields.append(field) }
            if scanner.isDone { break }
        }
        return fields.isEmpty ? kind : "\(kind) \(fields.joined(separator: ", "))"
    }
}

/// Collects field names directly inside the outermost selection set (aliases and arguments skipped).
private struct FieldScanner {
    private var depth = 0
    private var parentheses = 0
    private var word = ""
    private(set) var isDone = false

    mutating func feed(_ character: Character) -> String? {
        let isWordCharacter = character.isLetter || character.isNumber || character == "_"
        let collecting = depth == 1 && parentheses == 0
        if collecting, isWordCharacter {
            word.append(character)
            return nil
        }
        var finished: String?
        if collecting, !word.isEmpty {
            // `alias: field` — the word before a colon is an alias, not the field.
            finished = character == ":" ? nil : word
            word = ""
        }
        switch character {
        case "{": depth += 1
        case "}":
            depth -= 1
            if depth == 0 { isDone = true }
        case "(": parentheses += 1
        case ")": parentheses -= 1
        default: break
        }
        return finished
    }
}
