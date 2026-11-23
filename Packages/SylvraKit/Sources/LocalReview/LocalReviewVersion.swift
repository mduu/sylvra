import Foundation

/// The version of the Sylvra app the tool ships in (`Sylvra.app/Contents/Helpers/sylvra`).
public enum LocalReviewVersion {
    public static func fromAppBundle(executable: URL = URL(fileURLWithPath: CommandLine.arguments[0])) -> String? {
        let contents = executable.resolvingSymlinksInPath().deletingLastPathComponent().deletingLastPathComponent()
        let plist = contents.appending(path: "Info.plist")
        guard let info = NSDictionary(contentsOf: plist) else { return nil }
        return info["CFBundleShortVersionString"] as? String
    }
}
