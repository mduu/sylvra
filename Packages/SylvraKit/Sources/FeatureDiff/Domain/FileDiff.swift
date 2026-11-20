import Foundation

/// The diff of one file (see specs/architecture.md §7).
public struct FileDiff: Identifiable, Hashable, Sendable {
    public enum Status: String, Sendable {
        case added, deleted, modified, renamed
    }

    public var id: String { path }
    /// Path after the change (`new` side). For deleted files the old path.
    public let path: String
    /// Previous path for renames.
    public let previousPath: String?
    public let status: Status
    public let isBinary: Bool
    public let hunks: [Hunk]

    public init(path: String, previousPath: String? = nil, status: Status, isBinary: Bool = false, hunks: [Hunk]) {
        self.path = path
        self.previousPath = previousPath
        self.status = status
        self.isBinary = isBinary
        self.hunks = hunks
    }

    public var additions: Int { hunks.reduce(0) { $0 + $1.lines.count { $0.kind == .added } } }
    public var deletions: Int { hunks.reduce(0) { $0 + $1.lines.count { $0.kind == .removed } } }
    public var kind: FileKind { FileClassifier.classify(path) }
    public var fileName: String { (path as NSString).lastPathComponent }
    public var directory: String { (path as NSString).deletingLastPathComponent }
}

/// A contiguous block of changes with surrounding context.
public struct Hunk: Hashable, Sendable {
    public let oldStart: Int
    public let oldCount: Int
    public let newStart: Int
    public let newCount: Int
    /// Text after the second `@@`, usually the enclosing function or type.
    public let section: String
    public var lines: [DiffLine]

    public init(oldStart: Int, oldCount: Int, newStart: Int, newCount: Int, section: String = "", lines: [DiffLine]) {
        self.oldStart = oldStart
        self.oldCount = oldCount
        self.newStart = newStart
        self.newCount = newCount
        self.section = section
        self.lines = lines
    }

    public var header: String {
        "@@ -\(oldStart),\(oldCount) +\(newStart),\(newCount) @@" + (section.isEmpty ? "" : " \(section)")
    }
}

extension Hunk {
    /// The line in the new version (the pull request's head) to open for a line of this hunk: its own new line,
    /// for a removed line the next line that still exists (else the previous one, else the hunk's start).
    public func headLine(for line: DiffLine) -> Int {
        if let number = line.newNumber { return number }
        guard let index = lines.firstIndex(of: line) else { return max(newStart, 1) }
        let after = lines[index...].lazy.compactMap(\.newNumber).first
        let before = lines[..<index].reversed().lazy.compactMap(\.newNumber).first
        return after ?? before ?? max(newStart, 1)
    }
}

/// One line of a hunk.
public struct DiffLine: Hashable, Sendable {
    public enum Kind: Sendable {
        case context, added, removed
    }

    public let kind: Kind
    public let oldNumber: Int?
    public let newNumber: Int?
    public let text: String
    /// Character ranges (UTF-16 offsets) that changed compared to the paired line.
    public var highlights: [Range<Int>]
    /// The file has no trailing newline after this line.
    public var missingNewline: Bool

    public init(
        kind: Kind,
        oldNumber: Int?,
        newNumber: Int?,
        text: String,
        highlights: [Range<Int>] = [],
        missingNewline: Bool = false
    ) {
        self.kind = kind
        self.oldNumber = oldNumber
        self.newNumber = newNumber
        self.text = text
        self.highlights = highlights
        self.missingNewline = missingNewline
    }
}
