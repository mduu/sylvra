import Foundation

/// The app's version as shown in Settings, e.g. "0.5.15 (20)".
public enum AppVersion {
    public static func display(info: [String: Any]? = Bundle.main.infoDictionary) -> String {
        let version = info?["CFBundleShortVersionString"] as? String ?? "–"
        guard let build = info?["CFBundleVersion"] as? String, !build.isEmpty else { return version }
        return "\(version) (\(build))"
    }
}
