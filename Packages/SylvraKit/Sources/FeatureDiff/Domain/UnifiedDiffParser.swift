import Foundation

/// Parses `git diff` / GitHub unified diffs into `FileDiff`s and computes intra-line highlights.
public enum UnifiedDiffParser {
    public static func parse(_ text: String) -> [FileDiff] {
        var files: [FileDiff] = []
        var builder: FileBuilder?

        for rawLine in text.split(separator: "\n", omittingEmptySubsequences: false) {
            let line = rawLine.hasSuffix("\r") ? String(rawLine.dropLast()) : String(rawLine)
            if line.hasPrefix("diff --git ") {
                if let finished = builder?.build() { files.append(finished) }
                builder = FileBuilder(gitHeader: line)
            } else if builder == nil, line.hasPrefix("--- ") {
                builder = FileBuilder(gitHeader: nil)  // plain unified diff without git header
                builder?.consume(line)
            } else {
                builder?.consume(line)
            }
        }
        if let finished = builder?.build() { files.append(finished) }
        return files
    }
}

private struct FileBuilder {
    var oldPath: String?
    var newPath: String?
    var isNew = false
    var isDeleted = false
    var isRename = false
    var isBinary = false
    var hunks: [Hunk] = []
    var oldLine = 0
    var newLine = 0

    init(gitHeader: String?) {
        guard let gitHeader else { return }
        // "diff --git a/path b/path" — only used as fallback when ---/+++ are missing (e.g. pure renames).
        let rest = gitHeader.dropFirst("diff --git ".count)
        if let range = rest.range(of: " b/") {
            oldPath = String(rest[rest.startIndex..<range.lowerBound]).removingPrefix("a/")
            newPath = String(rest[range.upperBound...])
        }
    }

    mutating func consume(_ line: String) {
        if !hunks.isEmpty, let first = line.first, "+- \\".contains(first) {
            consumeHunkLine(line)
            return
        }
        if line.hasPrefix("@@") {
            startHunk(line)
        } else if line.hasPrefix("--- ") || line.hasPrefix("+++ ") {
            consumePathLine(line)
        } else if !hunks.isEmpty, line.isEmpty {
            // Some tools strip the leading space of empty context lines.
            consumeHunkLine(" ")
        } else {
            consumeMetadata(line)
        }
    }

    private mutating func consumePathLine(_ line: String) {
        let path = String(line.dropFirst(4))
        if line.hasPrefix("--- ") {
            if path == "/dev/null" { isNew = true } else { oldPath = path.removingPrefix("a/") }
        } else {
            if path == "/dev/null" { isDeleted = true } else { newPath = path.removingPrefix("b/") }
        }
    }

    private mutating func consumeMetadata(_ line: String) {
        if line.hasPrefix("new file mode") {
            isNew = true
        } else if line.hasPrefix("deleted file mode") {
            isDeleted = true
        } else if line.hasPrefix("rename from ") {
            isRename = true
            oldPath = String(line.dropFirst("rename from ".count))
        } else if line.hasPrefix("rename to ") {
            isRename = true
            newPath = String(line.dropFirst("rename to ".count))
        } else if line.hasPrefix("Binary files ") || line == "GIT binary patch" {
            isBinary = true
        }
    }

    private mutating func startHunk(_ line: String) {
        // @@ -oldStart,oldCount +newStart,newCount @@ section
        let parts = line.split(separator: "@@", maxSplits: 2, omittingEmptySubsequences: false)
        guard parts.count >= 2 else { return }
        let ranges = parts[1].split(separator: " ")
        let old = Self.range(ranges.first { $0.hasPrefix("-") })
        let new = Self.range(ranges.first { $0.hasPrefix("+") })
        let section = parts.count > 2 ? parts[2].trimmingCharacters(in: .whitespaces) : ""
        hunks.append(
            Hunk(
                oldStart: old.start, oldCount: old.count, newStart: new.start, newCount: new.count,
                section: section, lines: []))
        oldLine = old.start
        newLine = new.start
    }

    private static func range(_ token: Substring?) -> (start: Int, count: Int) {
        guard let token else { return (0, 0) }
        let numbers = token.dropFirst().split(separator: ",").compactMap { Int($0) }
        return (numbers.first ?? 0, numbers.count > 1 ? numbers[1] : 1)
    }

    private mutating func consumeHunkLine(_ line: String) {
        guard var hunk = hunks.popLast() else { return }
        defer { hunks.append(hunk) }
        let text = String(line.dropFirst())
        switch line.first {
        case "+":
            hunk.lines.append(DiffLine(kind: .added, oldNumber: nil, newNumber: newLine, text: text))
            newLine += 1
        case "-":
            hunk.lines.append(DiffLine(kind: .removed, oldNumber: oldLine, newNumber: nil, text: text))
            oldLine += 1
        case "\\":
            if var last = hunk.lines.popLast() {
                last.missingNewline = true
                hunk.lines.append(last)
            }
        default:
            hunk.lines.append(DiffLine(kind: .context, oldNumber: oldLine, newNumber: newLine, text: text))
            oldLine += 1
            newLine += 1
        }
    }

    func build() -> FileDiff? {
        guard let path = (isDeleted ? oldPath : newPath) ?? oldPath ?? newPath else { return nil }
        let status: FileDiff.Status =
            isNew
            ? .added
            : isDeleted ? .deleted : (isRename || (oldPath != nil && oldPath != newPath)) ? .renamed : .modified
        let previous = status == .renamed ? oldPath : nil
        return FileDiff(
            path: path, previousPath: previous, status: status, isBinary: isBinary,
            hunks: hunks.map(IntraLineDiff.annotate))
    }
}

extension String {
    fileprivate func removingPrefix(_ prefix: String) -> String {
        hasPrefix(prefix) ? String(dropFirst(prefix.count)) : self
    }
}
