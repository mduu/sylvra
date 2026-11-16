import Foundation
import OSLog

/// Unified logging for Sylvra. Entries are visible in Console.app (subsystem `com.marcduerst.sylvra`)
/// and in the app's diagnostic log window.
public enum SylvraLog {
    public static let subsystem = "com.marcduerst.sylvra"

    public static func logger(_ category: String) -> Logger {
        Logger(subsystem: subsystem, category: category)
    }
}

/// A log entry of this app run.
public struct DiagnosticLogEntry: Identifiable, Sendable, Equatable {
    public enum Level: String, Sendable {
        case debug, info, notice, error, fault
    }

    public let id: Int
    public let date: Date
    public let level: Level
    public let category: String
    public let message: String

    public init(id: Int, date: Date, level: Level, category: String, message: String) {
        self.id = id
        self.date = date
        self.level = level
        self.category = category
        self.message = message
    }

    /// One line for copying: `14:03:22.120 error github: …`.
    public var line: String {
        "\(date.formatted(.iso8601.time(includingFractionalSeconds: true))) \(level.rawValue) \(category): \(message)"
    }
}

/// Reads Sylvra's log entries of the current app run (no special entitlements needed).
public enum DiagnosticLog {
    /// Entries of the current process, oldest first. Debug entries are left out.
    public static func entries(since date: Date = .distantPast) throws -> [DiagnosticLogEntry] {
        let store = try OSLogStore(scope: .currentProcessIdentifier)
        let position = store.position(date: max(date, Date.now.addingTimeInterval(-24 * 3600)))
        let predicate = NSPredicate(format: "subsystem == %@", SylvraLog.subsystem)
        return try store.getEntries(at: position, matching: predicate)
            .compactMap { $0 as? OSLogEntryLog }
            .enumerated()
            .compactMap { index, entry in
                guard let level = level(entry.level) else { return nil }
                return DiagnosticLogEntry(
                    id: index, date: entry.date, level: level, category: entry.category,
                    message: entry.composedMessage)
            }
    }

    private static func level(_ level: OSLogEntryLog.Level) -> DiagnosticLogEntry.Level? {
        switch level {
        case .info: .info
        case .notice: .notice
        case .error: .error
        case .fault: .fault
        default: nil
        }
    }
}
