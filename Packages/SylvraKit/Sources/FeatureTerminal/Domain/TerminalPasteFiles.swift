import Foundation

/// Files and images for the terminal: what is pasted or dropped becomes a path the program reads (pure parts
/// unit-tested). Claude Code reads an image path as an image.
public enum TerminalPasteFiles {
    /// Where pasted and dropped images are written; files older than a day are removed on the next paste.
    public static var directory: URL {
        FileManager.default.temporaryDirectory.appending(path: "sylvra-paste", directoryHint: .isDirectory)
    }

    /// Paths as a shell would read them, like Terminal.app types them on a drop: separated by spaces, special
    /// characters escaped with a backslash.
    public static func text(for paths: [String]) -> String {
        paths.map(escaped).joined(separator: " ")
    }

    static func escaped(_ path: String) -> String {
        let special = Set(" \t\\'\"()[]{}<>|&;$`!*?#~=%^,")
        return path.reduce(into: "") { result, character in
            if special.contains(character) { result.append("\\") }
            result.append(character)
        }
    }

    /// Writes `png` as a new file in `directory` (after removing old ones) and returns its path.
    public static func save(png: Data, in directory: URL = directory, now: Date = .now) throws -> URL {
        let manager = FileManager.default
        try manager.createDirectory(at: directory, withIntermediateDirectories: true)
        removeOldFiles(in: directory, now: now)
        let stamp = ISO8601DateFormatter.string(
            from: now, timeZone: .current, formatOptions: [.withFullDate, .withTime, .withColonSeparatorInTime]
        )
        .replacingOccurrences(of: ":", with: ".")
        let file = directory.appending(path: "Image \(stamp) \(UUID().uuidString.prefix(4)).png")
        try png.write(to: file, options: .atomic)
        return file
    }

    /// Removes files older than a day: they were read long ago.
    static func removeOldFiles(in directory: URL, now: Date) {
        let manager = FileManager.default
        let files =
            (try? manager.contentsOfDirectory(at: directory, includingPropertiesForKeys: [.contentModificationDateKey]))
            ?? []
        for file in files {
            let modified = (try? file.resourceValues(forKeys: [.contentModificationDateKey]))?.contentModificationDate
            if let modified, now.timeIntervalSince(modified) > 86_400 { try? manager.removeItem(at: file) }
        }
    }
}
