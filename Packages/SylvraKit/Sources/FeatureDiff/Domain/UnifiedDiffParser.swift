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
    /// Lines still expected in the current hunk (from its header); 0 when the hunk is complete.
    var remainingOld = 0
    var remainingNew = 0
    var isInHunk: Bool { remainingOld > 0 || remainingNew > 0 }

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
        if line.hasPrefix("\\"), !hunks.isEmpty {
            consumeHunkLine(line)  // "\ No newline at end of file" may follow the last line of a hunk
            return
        }
        if isInHunk, !line.hasPrefix("@@ ") {  // a new header ends a hunk with a miscounted header
            // Some tools strip the leading space of empty context lines.
            consumeHunkLine(line.isEmpty ? " " : line)
            return
        }
        if line.hasPrefix("@@") {
            startHunk(line)
        } else if line.hasPrefix("--- ") || line.hasPrefix("+++ ") {
            consumePathLine(line)
        } else {
            consumeMetadata(line)
        }
    }

    private mutating func consumePathLine(_ line: String) {
        let path = String(line.dropFirst(4))
        if line.hasPrefix("--- ") {
            if path == "/dev/null" { isNew = true } else { oldPath = GitPath.decode(path).removingPrefix("a/") }
        } else {
            if path == "/dev/null" { isDeleted = true } else { newPath = GitPath.decode(path).removingPrefix("b/") }
        }
    }

    private mutating func consumeMetadata(_ line: String) {
        if line.hasPrefix("new file mode") {
            isNew = true
        } else if line.hasPrefix("deleted file mode") {
            isDeleted = true
        } else if line.hasPrefix("rename from ") {
            isRename = true
            oldPath = GitPath.decode(String(line.dropFirst("rename from ".count)))
        } else if line.hasPrefix("rename to ") {
            isRename = true
            newPath = GitPath.decode(String(line.dropFirst("rename to ".count)))
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
        remainingOld = old.count
        remainingNew = new.count
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
            remainingNew -= 1
        case "-":
            hunk.lines.append(DiffLine(kind: .removed, oldNumber: oldLine, newNumber: nil, text: text))
            oldLine += 1
            remainingOld -= 1
        case "\\":
            if var last = hunk.lines.popLast() {
                last.missingNewline = true
                hunk.lines.append(last)
            }
        default:
            hunk.lines.append(DiffLine(kind: .context, oldNumber: oldLine, newNumber: newLine, text: text))
            oldLine += 1
            newLine += 1
            remainingOld -= 1
            remainingNew -= 1
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

/// Git path quoting: a trailing tab after `---`/`+++` paths with spaces, C-quoted names with octal UTF-8 escapes.
enum GitPath {
    static func decode(_ raw: String) -> String {
        var path = raw
        if let tab = path.firstIndex(of: "\t") { path = String(path[..<tab]) }
        guard path.count >= 2, path.hasPrefix("\""), path.hasSuffix("\"") else { return path }
        var bytes: [UInt8] = []
        var iterator = Array(path.dropFirst().dropLast().utf8).makeIterator()
        while let byte = iterator.next() {
            guard byte == UInt8(ascii: "\\"), let escaped = iterator.next() else {
                bytes.append(byte)
                continue
            }
            switch escaped {
            case UInt8(ascii: "n"): bytes.append(10)
            case UInt8(ascii: "t"): bytes.append(9)
            case UInt8(ascii: "0")...UInt8(ascii: "7"):
                var value = Int(escaped - UInt8(ascii: "0"))
                for _ in 0..<2 {
                    guard let digit = iterator.next() else { break }
                    value = value * 8 + Int(digit - UInt8(ascii: "0"))
                }
                bytes.append(UInt8(truncatingIfNeeded: value))
            default: bytes.append(escaped)
            }
        }
        return String(decoding: bytes, as: UTF8.self)
    }
}
