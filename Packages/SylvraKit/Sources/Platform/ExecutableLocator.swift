import Foundation

/// Finds command line tools (`git`, `gh`, `claude`, IDE launchers).
///
/// GUI apps on macOS do not inherit the user's shell `PATH`, so well-known install locations
/// (Homebrew, `~/.local/bin`, …) are searched in addition to the inherited `PATH`.
public enum ExecutableLocator {
    /// Directories searched in order.
    public static var searchDirectories: [String] {
        let home = FileManager.default.homeDirectoryForCurrentUser.path
        let inherited = (ProcessInfo.processInfo.environment["PATH"] ?? "").split(separator: ":").map(String.init)
        let wellKnown = [
            "/opt/homebrew/bin",
            "/usr/local/bin",
            "\(home)/.local/bin",
            "\(home)/bin",
            "/usr/bin",
            "/bin",
            "/usr/sbin",
            "/sbin",
        ]
        var seen = Set<String>()
        return (wellKnown + inherited).filter { seen.insert($0).inserted }
    }

    /// Environment for child processes: the inherited one with an extended `PATH`.
    public static var environment: [String: String] {
        var environment = ProcessInfo.processInfo.environment
        environment["PATH"] = searchDirectories.joined(separator: ":")
        return environment
    }

    /// Returns the URL of the first executable named `name`, or `nil`.
    public static func locate(_ name: String) -> URL? {
        if name.hasPrefix("/") {
            return FileManager.default.isExecutableFile(atPath: name) ? URL(fileURLWithPath: name) : nil
        }
        for directory in searchDirectories {
            let path = (directory as NSString).appendingPathComponent(name)
            if FileManager.default.isExecutableFile(atPath: path) {
                return URL(fileURLWithPath: path)
            }
        }
        return nil
    }
}
